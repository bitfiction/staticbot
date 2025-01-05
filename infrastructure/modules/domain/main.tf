terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 5.0"
      configuration_aliases = [aws.certificates]
    }
  }
}

# Route53 zone for the domain
resource "aws_route53_zone" "main" {
  name = var.domain_name

  tags = {
    Business = var.business
  }
}

# ACM Certificate
resource "aws_acm_certificate" "cert" {
  provider = aws.certificates

  domain_name               = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
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
    if !contains(["*.${var.domain_name}"], dvo.domain_name) # Skip wildcard domain validation
  }

  zone_id         = aws_route53_zone.main.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true # Allow overwriting existing records
}

# Wait for certificate validation
resource "aws_acm_certificate_validation" "cert" {
  provider = aws.certificates

  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}
