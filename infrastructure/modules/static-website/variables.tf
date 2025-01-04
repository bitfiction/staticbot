# Variables
variable "domain_name" {
  type        = string
  description = "Primary domain name"
}

variable "subdomains" {
  type        = list(string)
  description = "List of subdomains"
}

variable "index_page" {
  type        = string
  description = "Index document filename"
}

variable "error_page" {
  type        = string
  description = "Error document filename"
}

variable "environment" {
  type        = string
  description = "Environment name (e.g., production, staging, development)"
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
