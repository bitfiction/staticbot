# infrastructure/modules/static-website/variables.tf

variable "business" {
  type        = string
  description = "Business name (e.g., bitfiction, guidedleap, ...)"
}

variable "domain_name" {
  description = "Primary domain name for the website"
  type        = string
}

variable "stage_subdomain" {
  description = "Subdomain for this stage"
  type        = string
}

variable "content_path" {
  description = "Path to the website content"
  type        = string
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
