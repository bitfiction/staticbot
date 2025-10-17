# infrastructure/variables.tf

variable "account_name" {
  description = "Account name (bitfiction, guidedleap, agentdev)"
  type        = string
}

variable "aws_account" {
  description = "AWS account configuration"
  type = object({
    account_id = string
    role_arn   = string
    region     = string
    external_id = string
  })
}

variable "websites" {
  description = "Configuration for websites in this accounts"
  type = map(object({
    domain_name = string
    use_existing_certificate        = optional(bool, false)
    use_existing_certificate_domain = optional(string, null)
    use_existing_hosted_zone       = optional(bool, false)
    use_existing_hosted_zone_id    = optional(string, null)

    # For single subdomain deployment
    subdomain               = optional(string)
    content_path            = optional(string)
    maintenance_mode        = optional(bool, false)
    maintenance_allowed_ips = optional(list(string), [])

    # For multi-stage deployments
    stages = optional(list(object({
      name                    = string
      subdomain               = string
      www_redirect            = bool
      content_path            = string
      maintenance_mode        = bool
      maintenance_allowed_ips = list(string)
    })))
  }))
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    ManagedBy = "Terraform"
  }
}
