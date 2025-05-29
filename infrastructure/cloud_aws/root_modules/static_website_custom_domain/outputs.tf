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
