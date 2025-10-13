terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 5.0"
      configuration_aliases = [aws.certificates]
    }
  }
}

data "aws_route53_zone" "existing" {
  count = var.use_existing_hosted_zone ? 1 : 0

  zone_id = var.use_existing_hosted_zone_id
}

data "aws_acm_certificate" "existing" {
  provider = aws.certificates
  count    = var.use_existing_certificate ? 1 : 0

  domain      = var.use_existing_certificate_domain
  most_recent = true
  statuses    = ["ISSUED"]
}

# Route53 zone for the domain
resource "aws_route53_zone" "main" {
  count = var.use_existing_hosted_zone ? 0 : 1

  name = var.domain_name

  tags = {
    Account = var.account_name
  }
}

# ACM Certificate
resource "aws_acm_certificate" "cert" {
  provider = aws.certificates
  count    = var.use_existing_certificate ? 0 : 1

  domain_name               = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# Validate ACM certificate
resource "aws_route53_record" "cert_validation" {
  for_each = var.use_existing_certificate ? {} : {
    for dvo in aws_acm_certificate.cert[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
    if !contains(["*.${var.domain_name}"], dvo.domain_name) # Skip wildcard domain validation
  }

  zone_id         = var.use_existing_hosted_zone ? data.aws_route53_zone.existing[0].zone_id : aws_route53_zone.main[0].zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true # Allow overwriting existing records
}

# Wait for certificate validation
resource "aws_acm_certificate_validation" "cert" {
  provider = aws.certificates
  count    = var.use_existing_certificate ? 0 : 1

  certificate_arn         = aws_acm_certificate.cert[0].arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}
