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

# Per-stack 301/302/307/308 redirects emitted at the edge by the viewer-request
# CloudFront Function before path rewriting. Optional; default empty preserves
# behaviour for sites that don't use this. Populated from the Stack edit page's
# Redirects field via staticbot-app's RedirectsParser → HCL list-of-objects.
variable "redirects" {
  description = "Exact-path redirect rules (from → to with status). Default: no redirects."
  type = list(object({
    from   = string
    to     = string
    status = number
  }))
  default = []
}

# Public base URL of the customer's own Supabase bucket holding migrated builder media, e.g.
# "https://<ref>.supabase.co/storage/v1/object/public/builder-assets/lovable". Set by
# staticbot-app from the website template's VITE_SUPABASE_URL; empty for every site that never came
# from a builder. When set, the distribution gains a second origin and a "/__l5e/*" behaviour that
# PROXIES those bytes — see builder-assets.tf for why proxied and never copied.
variable "builder_asset_base_url" {
  description = "Supabase public base URL for migrated builder assets served at /__l5e/*. Empty disables the route entirely."
  type        = string
  default     = ""

  validation {
    condition     = var.builder_asset_base_url == "" || can(regex("^https://[^/]+/.+", var.builder_asset_base_url))
    error_message = "builder_asset_base_url must be empty or an https URL with a path (host alone gives CloudFront no origin_path)."
  }
}
