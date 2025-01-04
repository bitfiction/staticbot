# infrastructure/modules/static-website/outputs.tf

output "cloudfront_url" {
  value = aws_cloudfront_distribution.website.domain_name
}

output "nameservers" {
  value = aws_route53_zone.main.name_servers
}

output "website_endpoint" {
  value = "https://${var.stage_subdomain}.${var.domain_name}"
}

output "certificate_arn" {
  value = aws_acm_certificate.cert.arn
}

output "s3_bucket" {
  value = aws_s3_bucket.website.id
}