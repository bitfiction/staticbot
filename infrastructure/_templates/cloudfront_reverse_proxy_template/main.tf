terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Primary provider — region where CloudFront distribution is managed.
# CloudFront is a global service but the distribution resource lives in the
# provider's region. ACM certificates for CloudFront MUST be in us-east-1.
provider "aws" {
  region = "us-east-1"

  dynamic "assume_role" {
    for_each = var.terraform_role_arn != "" ? [1] : []
    content {
      role_arn    = var.terraform_role_arn
      external_id = var.external_id
    }
  }

  default_tags {
    tags = var.common_tags
  }
}

locals {
  sanitized_name = replace(replace(replace(var.project_name, ".", "-"), "/--+/", "-"), "/-$/", "")

  # Resolve origin domains from region presets or direct overrides
  api_origin_domain = coalesce(
    var.api_origin_domain,
    var.posthog_region == "eu" ? "eu.i.posthog.com" : "us.i.posthog.com"
  )
  assets_origin_domain = coalesce(
    var.assets_origin_domain,
    var.posthog_region == "eu" ? "eu-assets.i.posthog.com" : "us-assets.i.posthog.com"
  )

  has_custom_domain = var.custom_domain != ""

  # Normalize string booleans from Python-generated tfvars ("True"/"true"/"false")
  _use_existing_hosted_zone  = lower(var.use_existing_hosted_zone) == "true"
  _use_existing_certificate  = lower(var.use_existing_certificate) == "true"

  # Derive the parent domain for hosted zone lookup (e.g. "events.example.com" → "example.com")
  domain_parts      = local.has_custom_domain ? split(".", var.custom_domain) : []
  parent_domain     = local.has_custom_domain && length(local.domain_parts) > 2 ? join(".", slice(local.domain_parts, 1, length(local.domain_parts))) : var.custom_domain

  # Resolved zone ID — from existing data source, explicit var, or newly created (not applicable here, proxy uses existing or provided)
  resolved_zone_id = local.has_custom_domain ? (
    local._use_existing_hosted_zone && var.use_existing_hosted_zone_id != ""
      ? data.aws_route53_zone.existing_by_id[0].zone_id
      : local._use_existing_hosted_zone
        ? data.aws_route53_zone.existing_by_name[0].zone_id
        : var.hosted_zone_id
  ) : ""

  # Resolved certificate ARN — from existing data source or newly created
  create_certificate = local.has_custom_domain && !local._use_existing_certificate
  resolved_certificate_arn = local.has_custom_domain ? (
    local._use_existing_certificate
      ? data.aws_acm_certificate.existing[0].arn
      : aws_acm_certificate_validation.proxy[0].certificate_arn
  ) : ""
}

# ---------------------------------------------------------------------------
# Look up existing Route53 Hosted Zone (when use_existing_hosted_zone is true)
# ---------------------------------------------------------------------------

data "aws_route53_zone" "existing_by_id" {
  count   = local._use_existing_hosted_zone && var.use_existing_hosted_zone_id != "" ? 1 : 0
  zone_id = var.use_existing_hosted_zone_id
}

data "aws_route53_zone" "existing_by_name" {
  count = local._use_existing_hosted_zone && var.use_existing_hosted_zone_id == "" ? 1 : 0
  name  = local.parent_domain
}

# ---------------------------------------------------------------------------
# Look up existing ACM Certificate (when use_existing_certificate is true)
# ---------------------------------------------------------------------------

data "aws_acm_certificate" "existing" {
  count       = local._use_existing_certificate && local.has_custom_domain ? 1 : 0
  domain      = var.use_existing_certificate_domain
  most_recent = true
  statuses    = ["ISSUED"]
}

# ---------------------------------------------------------------------------
# ACM Certificate (only when custom_domain is set and NOT reusing existing)
# ---------------------------------------------------------------------------

resource "aws_acm_certificate" "proxy" {
  count             = local.create_certificate ? 1 : 0
  domain_name       = var.custom_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = local.create_certificate ? {
    for dvo in aws_acm_certificate.proxy[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  zone_id         = local.resolved_zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "proxy" {
  count                   = local.create_certificate ? 1 : 0
  certificate_arn         = aws_acm_certificate.proxy[0].arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

# ---------------------------------------------------------------------------
# Route53 alias for the custom domain
# ---------------------------------------------------------------------------

resource "aws_route53_record" "proxy_alias" {
  count   = local.has_custom_domain ? 1 : 0
  zone_id = local.resolved_zone_id
  name    = var.custom_domain
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.proxy.domain_name
    zone_id                = aws_cloudfront_distribution.proxy.hosted_zone_id
    evaluate_target_health = false
  }
}

# ---------------------------------------------------------------------------
# CloudFront Cache Policy
# ---------------------------------------------------------------------------

resource "aws_cloudfront_cache_policy" "proxy" {
  name        = "${local.sanitized_name}-cache-policy"
  min_ttl     = 0
  default_ttl = 0
  max_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      # With caching disabled (max_ttl=0), cookie_behavior must be "none".
      # Cookies are still forwarded to the origin via the origin request policy.
      cookie_behavior = "none"
    }
    headers_config {
      # With caching disabled (max_ttl=0), header_behavior must be "none".
      # Headers are still forwarded to the origin via the origin request policy.
      header_behavior = "none"
    }
    query_strings_config {
      # With caching disabled (max_ttl=0), query_string_behavior must be "none".
      # Query strings are still forwarded to the origin via the origin request policy.
      query_string_behavior = "none"
    }

    enable_accept_encoding_brotli = false
    enable_accept_encoding_gzip   = false
  }
}

# ---------------------------------------------------------------------------
# CloudFront Origin Request Policy — forward everything except Host
# ---------------------------------------------------------------------------

resource "aws_cloudfront_origin_request_policy" "proxy" {
  name = "${local.sanitized_name}-origin-request-policy"

  cookies_config {
    cookie_behavior = "all"
  }
  headers_config {
    # Do NOT use "allViewer" — it forwards Host: g.staticbot.dev to the origin,
    # causing PostHog to return 404. CloudFront must send the origin's own Host header.
    header_behavior = "whitelist"
    headers {
      items = [
        "Origin",
        "Access-Control-Request-Headers",
        "Access-Control-Request-Method",
        "Referer",
        "Accept-Language",
      ]
    }
  }
  query_strings_config {
    query_string_behavior = "all"
  }
}

# ---------------------------------------------------------------------------
# CloudFront Response Headers Policy — CORS
# ---------------------------------------------------------------------------

resource "aws_cloudfront_response_headers_policy" "proxy" {
  name = "${local.sanitized_name}-cors-policy"

  cors_config {
    access_control_allow_credentials = true

    access_control_allow_headers {
      # Wildcard "*" is not allowed when allow_credentials is true (CORS spec).
      # List the specific headers needed by PostHog and general API usage.
      items = ["Authorization", "Content-Type", "Origin", "Accept", "X-Requested-With", "Cache-Control"]
    }
    access_control_allow_methods {
      items = ["GET", "POST", "OPTIONS", "PUT", "PATCH", "DELETE"]
    }
    access_control_allow_origins {
      items = length(var.cors_allow_origins) > 0 ? var.cors_allow_origins : ["*"]
    }
    access_control_expose_headers {
      items = ["Server-Timing"]
    }

    origin_override = true
  }
}

# ---------------------------------------------------------------------------
# CloudFront Distribution
# ---------------------------------------------------------------------------

resource "aws_cloudfront_distribution" "proxy" {
  enabled         = true
  comment         = "${var.project_name} reverse proxy"
  is_ipv6_enabled = true
  price_class     = var.price_class

  aliases = local.has_custom_domain ? [var.custom_domain] : []

  # --- API origin (default) ---
  origin {
    domain_name = local.api_origin_domain
    origin_id   = "api"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # --- Assets origin (/static/*) ---
  origin {
    domain_name = local.assets_origin_domain
    origin_id   = "assets"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # --- Default behavior → API ---
  default_cache_behavior {
    target_origin_id           = "api"
    viewer_protocol_policy     = "https-only"
    allowed_methods            = ["GET", "HEAD", "OPTIONS", "PUT", "PATCH", "POST", "DELETE"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = aws_cloudfront_cache_policy.proxy.id
    origin_request_policy_id   = aws_cloudfront_origin_request_policy.proxy.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.proxy.id
  }

  # --- /static/* → Assets origin ---
  ordered_cache_behavior {
    path_pattern               = "/static/*"
    target_origin_id           = "assets"
    viewer_protocol_policy     = "https-only"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = aws_cloudfront_cache_policy.proxy.id
    origin_request_policy_id   = aws_cloudfront_origin_request_policy.proxy.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.proxy.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    # Use ACM cert when custom domain is configured, otherwise default CloudFront cert
    acm_certificate_arn            = local.has_custom_domain ? local.resolved_certificate_arn : null
    cloudfront_default_certificate = local.has_custom_domain ? false : true
    minimum_protocol_version       = local.has_custom_domain ? "TLSv1.2_2021" : "TLSv1"
    ssl_support_method             = local.has_custom_domain ? "sni-only" : null
  }

  depends_on = [
    aws_cloudfront_cache_policy.proxy,
    aws_cloudfront_origin_request_policy.proxy,
    aws_cloudfront_response_headers_policy.proxy,
  ]
}
