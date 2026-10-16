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
  bucket = local.bucket_name
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

  # Second origin: the customer's OWN Supabase project, serving the builder media Phase 7 copied
  # there. Present only when the site has any — see builder-assets.tf. `origin_path` supplies the
  # /storage/v1/object/public/... prefix, which is why the attached function only has to strip
  # "/__l5e".
  dynamic "origin" {
    for_each = local.builder_assets_enabled ? [1] : []
    content {
      domain_name = local.builder_asset_host
      origin_id   = "builder-assets"
      origin_path = local.builder_asset_origin_path

      custom_origin_config {
        http_port              = 80
        https_port             = 443
        origin_protocol_policy = "https-only"
        origin_ssl_protocols   = ["TLSv1.2"]
      }
    }
  }

  # Evaluated before default_cache_behavior, so "/__l5e/*" never reaches the S3 origin (which would
  # answer with the SPA shell and a 200). No cookies and no Authorization forwarded: the visitor's
  # credentials must never reach the customer's Supabase project. Cached hard — the asset id in the
  # path changes whenever the bytes do.
  dynamic "ordered_cache_behavior" {
    for_each = local.builder_assets_enabled ? [1] : []
    content {
      path_pattern           = "/__l5e/*"
      target_origin_id       = "builder-assets"
      viewer_protocol_policy = "redirect-to-https"
      allowed_methods        = ["GET", "HEAD"]
      cached_methods         = ["GET", "HEAD"]
      compress               = true

      min_ttl     = 0
      default_ttl = 31536000
      max_ttl     = 31536000

      forwarded_values {
        query_string = false
        cookies {
          forward = "none"
        }
      }

      function_association {
        event_type   = "viewer-request"
        function_arn = aws_cloudfront_function.builder_assets[0].arn
      }

      # Turns the distribution-wide 404 -> index.html/200 rule back into an honest 404 on this
      # path, and sets the immutable cache header. See builder-assets.tf.
      function_association {
        event_type   = "viewer-response"
        function_arn = aws_cloudfront_function.builder_assets_response[0].arn
      }
    }
  }

  # Base44 function URLs → the customer's Supabase Edge Functions. See functions-proxy.tf.
  dynamic "origin" {
    for_each = local.functions_proxy_enabled ? [1] : []
    content {
      domain_name = local.functions_host
      origin_id   = "supabase-functions"
      origin_path = local.functions_origin_path

      custom_origin_config {
        http_port              = 80
        https_port             = 443
        origin_protocol_policy = "https-only"
        origin_ssl_protocols   = ["TLSv1.2"]
        # Edge functions (an LLM API among them) can take far longer than the 30s default.
        origin_read_timeout    = 60
      }
    }
  }

  dynamic "ordered_cache_behavior" {
    for_each = local.functions_proxy_enabled ? [1] : []
    content {
      path_pattern             = "/functions/*"
      target_origin_id         = "supabase-functions"
      viewer_protocol_policy   = "redirect-to-https"
      allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
      cached_methods           = ["GET", "HEAD"]
      compress                 = false
      cache_policy_id          = local.managed_cache_policy_caching_disabled
      origin_request_policy_id = local.managed_origin_request_policy_all_viewer_no_host

      function_association {
        event_type   = "viewer-request"
        function_arn = aws_cloudfront_function.functions_proxy[0].arn
      }
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

    # Single viewer-request handler: directory index routing + optional www redirect + optional maintenance mode
    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.viewer_request.arn
    }
  }

  # Custom error responses
  # None when the functions proxy is on: these are distribution-wide and would replace API error
  # responses with the SPA shell. The viewer-request function serves the shell instead.
  dynamic "custom_error_response" {
    for_each = local.functions_proxy_enabled ? {} : var.error_response_codes
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
    Account = var.account_name
    Domain  = var.domain_name
    Stage   = var.stage_subdomain
  }
}


# Upload index.html from content directory
resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.website.id
  key          = "index.html"
  source       = "${var.content_path}/index.html"
  content_type = "text/html"
  etag         = filemd5("${var.content_path}/index.html")

  lifecycle {
    ignore_changes = [
      source,
      etag,
      content_type,
    ]
  }
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
