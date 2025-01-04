# modules/static-website/main.tf

terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version              = "~> 5.0"
      configuration_aliases = [aws.certificates]
    }
  }
}

resource "aws_s3_bucket" "website" {
  bucket = "${var.environment}-${var.domain_name}"
}

resource "aws_s3_bucket_public_access_block" "website" {
  bucket = aws_s3_bucket.website.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_website_configuration" "website" {
  bucket = aws_s3_bucket.website.id

  index_document {
    suffix = var.index_page
  }

  error_document {
    key = var.error_page
  }
}

# ACM Certificate (using certificates provider)
resource "aws_acm_certificate" "cert" {
  provider = aws.certificates

  domain_name               = var.domain_name
  subject_alternative_names = [for subdomain in var.subdomains : "${subdomain}.${var.domain_name}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# Route53 zone
resource "aws_route53_zone" "main" {
  name = var.domain_name

  tags = {
    Environment = var.environment
  }
}

# Validate ACM certificate
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = aws_route53_zone.main.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60
}

# Wait for certificate validation
resource "aws_acm_certificate_validation" "cert" {
  provider = aws.certificates

  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# CloudFront distribution
resource "aws_cloudfront_distribution" "website" {
  origin {
    domain_name = aws_s3_bucket.website.bucket_regional_domain_name
    origin_id   = "S3-${var.domain_name}"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.oai.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = var.index_page

  aliases = concat([var.domain_name], [for subdomain in var.subdomains : "${subdomain}.${var.domain_name}"])

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-${var.domain_name}"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  price_class = "PriceClass_100"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.cert.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = {
    Environment = var.environment
  }
}

# CloudFront OAI
resource "aws_cloudfront_origin_access_identity" "oai" {
  comment = "OAI for ${var.environment}-${var.domain_name}"
}

# S3 bucket policy
resource "aws_s3_bucket_policy" "website" {
  bucket = aws_s3_bucket.website.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "CloudFrontAccess"
        Effect    = "Allow"
        Principal = {
          AWS = aws_cloudfront_origin_access_identity.oai.iam_arn
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.website.arn}/*"
      }
    ]
  })
}

# DNS records for each subdomain
resource "aws_route53_record" "subdomains" {
  for_each = toset(concat([var.domain_name], [for subdomain in var.subdomains : "${subdomain}.${var.domain_name}"]))

  zone_id = aws_route53_zone.main.zone_id
  name    = each.value
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.website.domain_name
    zone_id               = aws_cloudfront_distribution.website.hosted_zone_id
    evaluate_target_health = false
  }
}
