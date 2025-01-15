# infrastructure/environments/prod/main.tf

module "websites" {
  source = "../../" # This points to the root infrastructure directory

  account_name    = var.account_name
  aws_account = var.aws_account
  websites    = var.websites
  common_tags = var.common_tags
}

# Re-export the outputs from the root module
output "website_urls" {
  value = module.websites.website_urls
}
