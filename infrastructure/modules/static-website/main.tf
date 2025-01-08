# infrastructure/modules/static-website/main.tf

terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 5.0"
      configuration_aliases = [aws.certificates]
    }
  }
}

# Route53 record for apex domain
resource "aws_route53_record" "apex" {
  count = var.stage_subdomain == "www" ? 1 : 0
  
  zone_id = var.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.website.domain_name
    zone_id                = aws_cloudfront_distribution.website.hosted_zone_id
    evaluate_target_health = false
  }
}

# S3 bucket for website content
resource "aws_s3_bucket" "website" {
  bucket = "${var.business}-${var.domain_name}-${var.stage_subdomain}"
}

resource "aws_s3_bucket_public_access_block" "website" {
  bucket = aws_s3_bucket.website.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "website" {
  bucket = aws_s3_bucket.website.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "website" {
  bucket = aws_s3_bucket.website.id
  versioning_configuration {
    status = "Enabled"
  }
}


# CloudFront OAI
resource "aws_cloudfront_origin_access_identity" "oai" {
  comment = "OAI for ${var.domain_name} ${var.stage_subdomain}"
}

# CloudFront distribution
resource "aws_cloudfront_distribution" "website" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100"
  aliases             = var.stage_subdomain == "www" ? [var.domain_name, "${var.stage_subdomain}.${var.domain_name}"] : ["${var.stage_subdomain}.${var.domain_name}"]

  origin {
    domain_name = aws_s3_bucket.website.bucket_regional_domain_name
    origin_id   = local.s3_origin_id

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.oai.cloudfront_access_identity_path
    }
  }

  # Default cache behavior
  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD", "OPTIONS"]
    target_origin_id       = local.s3_origin_id
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      headers      = ["Origin", "Access-Control-Request-Headers", "Access-Control-Request-Method"]

      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400

    # Function associations
    dynamic "function_association" {
      for_each = var.www_redirect ? [1] : []
      content {
        event_type   = "viewer-request"
        function_arn = aws_cloudfront_function.www_redirect.arn
      }
    }

    dynamic "function_association" {
      for_each = var.maintenance_mode ? [1] : []
      content {
        event_type   = "viewer-request"
        function_arn = aws_cloudfront_function.maintenance_mode.arn
      }
    }
  }

  # Custom error responses
  dynamic "custom_error_response" {
    for_each = var.error_response_codes
    content {
      error_code            = custom_error_response.key
      response_code         = custom_error_response.value.response_code
      response_page_path    = custom_error_response.value.response_page_path
      error_caching_min_ttl = custom_error_response.value.error_caching_min_ttl
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = var.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = {
    Business = var.business
    Domain   = var.domain_name
    Stage    = var.stage_subdomain
  }
}


# Upload index.html from content directory
resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.website.id
  key          = "index.html"
  source       = "${var.content_path}/index.html"
  content_type = "text/html"
  etag         = filemd5("${var.content_path}/index.html")
}

# S3 bucket policy
resource "aws_s3_bucket_policy" "website" {
  bucket = aws_s3_bucket.website.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudFrontAccess"
        Effect = "Allow"
        Principal = {
          AWS = aws_cloudfront_origin_access_identity.oai.iam_arn
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.website.arn}/*"
      }
    ]
  })
}

# Route53 record for the stage
resource "aws_route53_record" "website" {
  zone_id = var.zone_id
  name    = "${var.stage_subdomain}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.website.domain_name
    zone_id                = aws_cloudfront_distribution.website.hosted_zone_id
    evaluate_target_health = false
  }
}
