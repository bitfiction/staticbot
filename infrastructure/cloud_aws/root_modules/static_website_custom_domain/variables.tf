# infrastructure/variables.tf

variable "aws_region" {
  description = "Default AWS region for resources"
  type        = string
  default     = "eu-central-1"
}

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
  })
}

variable "websites" {
  description = "Configuration for websites in this accounts"
  type = map(object({
    domain_name = string
    stages = list(object({
      name                    = string
      subdomain               = string
      www_redirect            = bool
      content_path            = string
      maintenance_mode        = bool
      maintenance_allowed_ips = list(string)
    }))
  }))
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    ManagedBy = "Terraform"
  }
}
