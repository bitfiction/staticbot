# Outputs
output "cloudfront_url" {
  value = aws_cloudfront_distribution.website.domain_name
}

output "nameservers" {
  value = aws_route53_zone.main.name_servers
}