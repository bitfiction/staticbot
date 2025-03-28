account_name = "<account_name>"

aws_account = {
  account_id = "<target_account_id>"
  role_arn = "<target_role_arn>"
  region   = "<target_region>"
}

websites = {
  "<websites_domain>" = {
    domain_name = "<websites_domain_name>"
    stages = [
      {
        name                    = "<websites_stage_name>"
        subdomain               = "<websites_stage_subdomain>"
        www_redirect            = <websites_stage_www_redirect>
        maintenance_mode        = <websites_stage_maintenance_mode>
        maintenance_allowed_ips = ["<websites_stage_maintenance_allowed_ips>"]
      }
    ]
  }
}

common_tags = {
  Account   = "<account_name>"
  DeployedBy = "Staticbot"
  ManagedBy  = "Terraform"
}
