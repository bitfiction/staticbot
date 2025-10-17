# infrastructure/main.tf

# Create domain resources once per domain
module "domains" {
  source = "../../modules/domain"

  for_each = {
    for website_key, website in var.websites : website_key => website
  }

  providers = {
    aws.certificates = aws.certificates
  }

  account_name = var.account_name
  domain_name  = each.value.domain_name

  use_existing_hosted_zone        = each.value.use_existing_hosted_zone
  use_existing_hosted_zone_id     = each.value.use_existing_hosted_zone_id
  use_existing_certificate        = each.value.use_existing_certificate
  use_existing_certificate_domain = each.value.use_existing_certificate_domain
}

# Create static websites for each stage
module "static_website" {
  source = "../../modules/static-website"

  for_each = {
    for deployment in local.website_stages :
    deployment.full_domain => deployment
  }

  providers = {
    aws.certificates = aws.certificates
  }

  domain_name     = each.value.domain_name
  stage_subdomain = each.value.subdomain
  account_name    = var.account_name
  content_path    = each.value.content_path

  # Pass existing domain resources
  zone_id         = module.domains[each.value.website_key].zone_id
  certificate_arn = module.domains[each.value.website_key].certificate_arn

  www_redirect            = try(each.value.www_redirect, false)
  maintenance_mode        = try(each.value.maintenance_mode, false)
  maintenance_allowed_ips = try(each.value.maintenance_allowed_ips, [])
}
