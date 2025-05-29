# infrastructure/locals.tf

locals {
  # Flatten website and stage combinations
  website_stages = flatten([
    for website_key, website in var.websites : [
      for stage in website.stages : {
        website_key             = website_key
        domain_name             = website.domain_name
        stage_name              = stage.name
        subdomain               = stage.subdomain
        www_redirect            = try(stage.www_redirect, false)
        maintenance_mode        = try(stage.maintenance_mode, false)
        maintenance_allowed_ips = try(stage.maintenance_allowed_ips, [])
        full_domain             = "${stage.subdomain}.${website.domain_name}"
        content_path            = coalesce(stage.content_path, "${path.module}/../../../../websites/${website.domain_name}/${stage.subdomain}") // fallback only for manual deployments
      }
    ]
  ])
}
