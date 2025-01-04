# infrastructure/businesses/accounts.tf

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
