# infrastructure/modules/static-website/variables.tf

variable "account_name" {
  type        = string
  description = "Account name (e.g., bitfiction, guidedleap, ...)"
}

variable "domain_name" {
  description = "Primary domain name for the website"
  type        = string
}

variable "zone_id" {
  description = "Route53 zone ID for the domain"
  type        = string
}

variable "certificate_arn" {
  description = "ACM certificate ARN for the domain"
  type        = string
}

variable "stage_subdomain" {
  description = "Subdomain for this stage"
  type        = string
}

variable "content_path" {
  description = "Path to the website content"
  type        = string

  validation {
    condition     = fileexists("${var.content_path}/index.html")
    error_message = "The content_path must contain an index.html file."
  }
}

variable "error_response_codes" {
  description = "Custom error response configuration"
  type = map(object({
    response_code         = number
    response_page_path    = string
    error_caching_min_ttl = number
  }))
  default = {
    "403" = {
      response_code         = 200
      response_page_path    = "/index.html"
      error_caching_min_ttl = 10 # Cache this rule for 10 seconds
    }
    "404" = {
      response_code         = 200
      response_page_path    = "/index.html"
      error_caching_min_ttl = 10 # Cache this rule for 10 seconds
    }
    "500" = {
      response_code         = 500
      response_page_path    = "/500.html"
      error_caching_min_ttl = 300
    }
  }
}

# Variables for www redirect control
variable "www_redirect" {
  description = "Enable/disable www redirect"
  type        = bool
  default     = false
}

# Variables for maintenance mode control
variable "maintenance_mode" {
  description = "Enable/disable maintenance mode"
  type        = bool
  default     = false
}

variable "maintenance_allowed_ips" {
  description = "IPs allowed to bypass maintenance mode"
  type        = list(string)
  default     = []
}
