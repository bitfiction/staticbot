# infrastructure/main.tf

locals {
  websites_with_cert_domain = {
    for website_key, website in var.websites : website_key => merge(website, {
      certificate_domain_name = try(website.subdomain, null) != null && can(regex("\\.", website.subdomain)) ? join(".", [join(".", slice(split(".", website.subdomain), 1, length(split(".", website.subdomain)))), website.domain_name]) : website.domain_name
    })
  }

  # Group by certificate domain name to avoid duplicate certificate requests
  unique_domains_map = {
    for key, val in local.websites_with_cert_domain : val.certificate_domain_name => val...
  }
}

# Create domain resources once per domain
module "domains" {
  source = "../../modules/domain"

  # Iterate over unique certificate domains, picking the first configuration
  for_each = {
    for domain, configs in local.unique_domains_map : domain => configs[0]
  }

  providers = {
    aws.certificates = aws.certificates
  }

  account_name            = var.account_name
  domain_name             = each.value.domain_name
  certificate_domain_name = each.key

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

  # Pass existing domain resources (lookup by certificate domain name)
  zone_id         = module.domains[local.websites_with_cert_domain[each.value.website_key].certificate_domain_name].zone_id
  certificate_arn = module.domains[local.websites_with_cert_domain[each.value.website_key].certificate_domain_name].certificate_arn

  www_redirect            = try(each.value.www_redirect, false)
  maintenance_mode        = try(each.value.maintenance_mode, false)
  maintenance_allowed_ips = try(each.value.maintenance_allowed_ips, [])
}
