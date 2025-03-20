account_name = "staticbot-dev"

aws_account = {
  account_id = "682033486080"
  //  for deployment via IAM role
  role_arn = "arn:aws:iam::682033486080:role/staticbot-dev-terraform-role"
  region   = "eu-central-1"
}

websites = {
  "staticbot.eu" = {
    domain_name = "staticbot.eu"
    stages = [
      {
        name                    = "dev"
        subdomain               = "dev"
        www_redirect            = false
        maintenance_mode        = false
        maintenance_allowed_ips = []
      }
    ]
  }
}

common_tags = {
  Account   = "bitfiction"
  DeployedBy = "Staticbot"
  ManagedBy  = "Terraform"
  Owner      = "DevOps"
}
