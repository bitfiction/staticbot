# infrastructure/modules/static-website/outputs.tf

output "cloudfront_url" {
  value = aws_cloudfront_distribution.website.domain_name
}

output "website_endpoint" {
  value = "https://${var.stage_subdomain}.${var.domain_name}"
}

output "s3_bucket" {
  value = aws_s3_bucket.website.id
}
