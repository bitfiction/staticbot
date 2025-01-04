# infrastructure/variables.tf

variable "aws_region" {
  description = "Default AWS region for resources"
  type        = string
  default     = "eu-central-1"
}

variable "business" {
  description = "Environment name (bitfiction, guidedleap, agentdev)"
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
  description = "Configuration for websites in this environment"
  type = map(object({
    domain_name = string
    stages = list(object({
      name      = string
      subdomain = string
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

# Module specific variables

# infrastructure/modules/static-website/variables.tf
variable "domain_name" {
  description = "Primary domain name for the website"
  type        = string
}

variable "stage_subdomain" {
  description = "Subdomain for this stage"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "content_path" {
  description = "Path to the website content"
  type        = string
}

variable "maintenance_mode" {
  description = "Enable maintenance mode"
  type        = bool
  default     = false
}

variable "maintenance_allowed_ips" {
  description = "IPs allowed during maintenance"
  type        = list(string)
  default     = []
}

variable "error_response_codes" {
  description = "Custom error response configuration"
  type = map(object({
    response_code         = number
    response_page_path   = string
    error_caching_min_ttl = number
  }))
  default = {
    "404" = {
      response_code         = 404
      response_page_path   = "/404.html"
      error_caching_min_ttl = 300
    }
    "500" = {
      response_code         = 500
      response_page_path   = "/500.html"
      error_caching_min_ttl = 300
    }
  }
}