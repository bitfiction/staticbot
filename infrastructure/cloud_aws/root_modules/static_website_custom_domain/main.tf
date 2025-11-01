# infrastructure/main.tf

locals {
  websites_with_cert_domain = {
    for website_key, website in var.websites : website_key => merge(website, {
      certificate_domain_name = try(website.subdomain, null) != null && can(regex("\\.", website.subdomain)) ? join(".", [join(".", slice(split(".", website.subdomain), 1, length(split(".", website.subdomain)))), website.domain_name]) : website.domain_name
    })
  }
}

# Create domain resources once per domain
module "domains" {
  source = "../../modules/domain"

  for_each = local.websites_with_cert_domain

  providers = {
    aws.certificates = aws.certificates
  }

  account_name            = var.account_name
  domain_name             = each.value.domain_name
  certificate_domain_name = each.value.certificate_domain_name

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
