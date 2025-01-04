# infrastructure/main.tf

module "static_website" {
  source = "./modules/static-website"
  
  for_each = {
    for deployment in local.website_stages : 
    "${deployment.website_key}-${deployment.stage_name}" => deployment
  }

  providers = {
    aws.certificates = aws.certificates
  }

  domain_name     = each.value.domain_name
  stage_subdomain = each.value.subdomain
  business        = var.business
  content_path    = each.value.content_path

  maintenance_mode = try(each.value.maintenance_mode, false)
  maintenance_allowed_ips = try(each.value.maintenance_allowed_ips, [])
}

# Outputs
output "website_urls" {
  description = "CloudFront URLs for each website stage"
  value = {
    for k, v in module.static_website : k => v.cloudfront_url
  }
}

output "nameservers" {
  description = "Nameservers for each domain"
  value = {
    for k, v in module.static_website : k => v.nameservers
  }
}