output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = aws_cloudfront_distribution.proxy.id
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name (*.cloudfront.net)"
  value       = aws_cloudfront_distribution.proxy.domain_name
}

output "proxy_url" {
  description = "URL to use as your proxy endpoint"
  value       = local.has_custom_domain ? "https://${var.custom_domain}" : "https://${aws_cloudfront_distribution.proxy.domain_name}"
}
