variable "account_name" {
  type        = string
  description = "Account name"
}

variable "domain_name" {
  type        = string
  description = "Primary domain name"
}

variable "use_existing_hosted_zone" {
  description = "Flag to use an existing hosted zone"
  type        = bool
  default     = false
}

variable "use_existing_hosted_zone_id" {
  description = "ID of the existing hosted zone"
  type        = string
  default     = null
}

variable "use_existing_certificate" {
  description = "Flag to use an existing certificate"
  type        = bool
  default     = false
}

variable "use_existing_certificate_domain" {
  description = "Domain name of the existing certificate"
  type        = string
  default     = null
}
