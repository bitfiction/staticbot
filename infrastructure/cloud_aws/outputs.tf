output "website_urls" {
  description = "CloudFront URLs for each website stage"
  value = {
    for k, v in module.static_website : k => v.cloudfront_url
  }
}
