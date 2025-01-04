# infrastructure/environments/accounts.tf

# Website configurations with account mappings
variable "websites" {
  description = "Map of websites and their AWS account assignments"
  type = map(object({
    domain_name = string
    aws_account = string  # Key from aws_accounts map
    stages = list(object({
      name      = string
      subdomain = string
    }))
  }))
}

# Add a local to help track which websites are in each account
locals {
  websites_by_account = {
    for account_key in keys(var.aws_accounts) : account_key => {
      for website_key, website in var.websites :
      website_key => website
      if website.aws_account == account_key
    }
  }
}