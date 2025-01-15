account_name = "bitfiction"

aws_account = {
  account_id = "729084315504"
  //  for deployment via IAM role
  role_arn = "arn:aws:iam::729084315504:role/bitfiction-terraform-role"
  region   = "eu-central-1"
}

websites = {
  "bitfiction.com" = {
    domain_name = "bitfiction.com"
    stages = [
      {
        name                    = "dev"
        subdomain               = "dev"
        www_redirect            = false
        maintenance_mode        = false
        maintenance_allowed_ips = []
      },
      {
        name                    = "production"
        subdomain               = "www"
        www_redirect            = true
        maintenance_mode        = false
        maintenance_allowed_ips = []
      }
    ]
  },
  "bitfiction.org" = {
    domain_name = "bitfiction.org"
    stages = [
      {
        name                    = "dev"
        subdomain               = "dev"
        www_redirect            = false
        maintenance_mode        = false
        maintenance_allowed_ips = []
      },
      {
        name                    = "production"
        subdomain               = "www"
        www_redirect            = true
        maintenance_mode        = false
        maintenance_allowed_ips = []
      }
    ]
  }
}

common_tags = {
  Business   = "bitfiction"
  DeployedBy = "Staticbot"
  ManagedBy  = "Terraform"
  Owner      = "DevOps"
}
