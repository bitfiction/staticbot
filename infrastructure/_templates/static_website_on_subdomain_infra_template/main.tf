module "websites" {
  source = "../../cloud_aws/root_modules/static_website_custom_domain"

  account_name = var.account_name
  aws_account  = var.aws_account
  websites = {
    for k, v in var.websites : k => {
      domain_name                     = v.parent_domain_name
      subdomain                       = v.subdomain_name
      use_existing_certificate        = v.use_existing_certificate
      use_existing_certificate_domain = v.use_existing_certificate_domain
      use_existing_hosted_zone        = v.use_existing_hosted_zone
      use_existing_hosted_zone_id     = v.use_existing_hosted_zone_id
      content_path                    = v.content_path
      maintenance_mode                = v.maintenance_mode
      maintenance_allowed_ips         = v.maintenance_allowed_ips
    }
  }
  common_tags = var.common_tags
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
