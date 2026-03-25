variable "project_name" {
  description = "Project name for tagging and naming resources"
  type        = string
  default     = "cloudfront-reverse-proxy"
}

# --- Staticbot role assumption (optional — leave empty for standalone use) ---

variable "terraform_role_arn" {
  description = "ARN of the IAM role to assume. Leave empty to use default credentials."
  type        = string
  default     = ""
}

variable "external_id" {
  description = "External ID for cross-account role assumption"
  type        = string
  default     = ""
}

# --- Origin configuration ---

variable "posthog_region" {
  description = "PostHog region shorthand: 'us' or 'eu'. Used to set default origin domains when api_origin_domain / assets_origin_domain are not explicitly provided."
  type        = string
  default     = "us"

  validation {
    condition     = contains(["us", "eu"], var.posthog_region)
    error_message = "posthog_region must be 'us' or 'eu'."
  }
}

variable "api_origin_domain" {
  description = "Domain for the API origin (default behavior). Overrides posthog_region. Example: us.i.posthog.com"
  type        = string
  default     = ""
}

variable "assets_origin_domain" {
  description = "Domain for the static assets origin (/static/*). Overrides posthog_region. Example: us-assets.i.posthog.com"
  type        = string
  default     = ""
}

# --- Custom domain (optional) ---

variable "custom_domain" {
  description = "Custom domain for the CloudFront distribution. Leave empty to use the default *.cloudfront.net domain."
  type        = string
  default     = ""
}

variable "hosted_zone_id" {
  description = "Route53 Hosted Zone ID for the custom domain. Required when custom_domain is set and use_existing_hosted_zone is false."
  type        = string
  default     = ""
}

# --- Reuse existing resources (when deploying into an account that already hosts websites) ---

variable "use_existing_hosted_zone" {
  description = "If true, look up an existing Route53 hosted zone instead of requiring hosted_zone_id. The zone is looked up by the parent domain of custom_domain."
  type        = bool
  default     = false
}

variable "use_existing_hosted_zone_id" {
  description = "Explicit hosted zone ID to use when use_existing_hosted_zone is true. If empty, the zone is looked up by domain name."
  type        = string
  default     = ""
}

variable "use_existing_certificate" {
  description = "If true, look up an existing ACM certificate instead of creating a new one."
  type        = bool
  default     = false
}

variable "use_existing_certificate_domain" {
  description = "Domain to look up the existing certificate for (e.g. '*.example.com' or 'example.com'). Required when use_existing_certificate is true."
  type        = string
  default     = ""
}

# --- CORS ---

variable "cors_allow_origins" {
  description = "Origins allowed by CORS. Defaults to ['*'] if empty."
  type        = list(string)
  default     = []
}

# --- Distribution settings ---

variable "price_class" {
  description = "CloudFront price class"
  type        = string
  default     = "PriceClass_100"
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    ManagedBy = "Terraform"
  }
}
