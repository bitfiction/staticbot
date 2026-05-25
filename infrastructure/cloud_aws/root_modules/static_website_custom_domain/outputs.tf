output "website_urls" {
  description = "CloudFront URLs for each website"
  value = {
    for k, v in module.static_website : k => v.cloudfront_url
  }
}

output "s3_buckets" {
  description = "S3 buckets for each website"
  value = {
    for k, v in module.static_website : k => v.s3_bucket
  }
}

output "website_endpoints" {
  description = "Website URLs for each website"
  value = {
    for k, v in module.static_website : k => v.website_endpoint
  }
}

output "cloudfront_distribution_ids" {
  description = "CloudFront distribution IDs for each website deployment"
  value = {
    for k, v in module.static_website : k => v.cloudfront_distribution_id
  }
}

output "nameservers" {
  description = "Authoritative nameservers per certificate domain — empty if the zone was reused (use_existing_hosted_zone)."
  value = {
    for k, v in module.domains : k => v.nameservers
  }
}
