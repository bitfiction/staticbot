module "websites" {
  source = "../../cloud_aws/root_modules/static_website_custom_domain"

  account_name = var.account_name
  aws_account  = var.aws_account
  websites     = var.websites
  common_tags  = var.common_tags
}

# Re-export the outputs from the root module
output "website_urls" {
  value = module.websites.website_urls
}

output "s3_buckets" {
  value = module.websites.s3_buckets
}

output "website_endpoints" {
  value = module.websites.website_endpoints
}

output "cloudfront_distribution_ids" {
  description = "CloudFront distribution IDs for each website"
  value       = module.websites.cloudfront_distribution_ids
}
