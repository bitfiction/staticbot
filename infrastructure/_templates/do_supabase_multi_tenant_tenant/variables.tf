# --- Tenant Identity ---

variable "tenant_id" {
  description = "Unique tenant identifier (used in namespace, DB name, subdomain)"
  type        = string
}

# --- Cluster Connection (from shared module outputs) ---

variable "cluster_endpoint" {
  description = "DOKS cluster API endpoint"
  type        = string
}

variable "cluster_token" {
  description = "DOKS cluster auth token"
  type        = string
  sensitive   = true
}

variable "cluster_ca_certificate" {
  description = "DOKS cluster CA certificate (base64)"
  type        = string
  sensitive   = true
}

# --- Shared Infrastructure References ---

variable "shared_db_host" {
  description = "Hostname of the shared PostgreSQL service (e.g. db.supabase-shared.svc.cluster.local)"
  type        = string
}

variable "shared_db_port" {
  description = "Port of the shared PostgreSQL service"
  type        = number
  default     = 5432
}

variable "shared_imgproxy_host" {
  description = "Hostname of the shared ImgProxy service"
  type        = string
}

variable "shared_namespace" {
  description = "Kubernetes namespace for shared services"
  type        = string
  default     = "supabase-shared"
}

variable "api_domain" {
  description = "Base API domain (e.g. sb.frever.net) — tenant gets {tenant_id}.{api_domain}"
  type        = string
}

# --- Database ---

variable "postgres_password" {
  description = "Password for shared Postgres (same across all tenants)"
  type        = string
  sensitive   = true
}

# --- Tenant Secrets ---

variable "jwt_secret" {
  description = "JWT Secret for this tenant"
  type        = string
  sensitive   = true
}

variable "anon_key" {
  description = "Anon Key for this tenant"
  type        = string
  sensitive   = true
}

variable "service_role_key" {
  description = "Service Role Key for this tenant"
  type        = string
  sensitive   = true
}

variable "jwt_expiry" {
  description = "JWT expiry in seconds"
  type        = number
  default     = 3600
}

# --- Opaque API Keys (ES256) ---

variable "supabase_publishable_key" {
  description = "Opaque API key for client-side use (anon role)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "supabase_secret_key" {
  description = "Opaque API key for server-side use (service_role)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "anon_key_asymmetric" {
  description = "Pre-signed ES256 JWT for anon role"
  type        = string
  sensitive   = true
  default     = ""
}

variable "service_role_key_asymmetric" {
  description = "Pre-signed ES256 JWT for service_role"
  type        = string
  sensitive   = true
  default     = ""
}

# --- Auth (GoTrue) ---

variable "site_url" {
  description = "Site URL (the user's app URL)"
  type        = string
}

variable "additional_redirect_urls" {
  description = "Additional redirect URLs (comma separated)"
  type        = string
  default     = ""
}

variable "disable_signup" {
  description = "Disable signup"
  type        = bool
  default     = false
}

variable "enable_email_signup" {
  description = "Enable email signup"
  type        = bool
  default     = true
}

variable "enable_anonymous_users" {
  description = "Enable anonymous users"
  type        = bool
  default     = false
}

variable "enable_email_autoconfirm" {
  description = "Enable email autoconfirm"
  type        = bool
  default     = false
}

variable "smtp_admin_email" {
  description = "SMTP admin email"
  type        = string
  default     = ""
}

variable "smtp_host" {
  description = "SMTP host"
  type        = string
  default     = ""
}

variable "smtp_port" {
  description = "SMTP port"
  type        = number
  default     = 587
}

variable "smtp_user" {
  description = "SMTP user"
  type        = string
  default     = ""
}

variable "smtp_pass" {
  description = "SMTP password"
  type        = string
  sensitive   = true
  default     = ""
}

variable "smtp_sender_name" {
  description = "SMTP sender name"
  type        = string
  default     = "Supabase"
}

variable "mailer_urlpaths_invite" {
  description = "Mailer URL path for invites"
  type        = string
  default     = "/auth/v1/verify"
}

variable "mailer_urlpaths_confirmation" {
  description = "Mailer URL path for confirmation"
  type        = string
  default     = "/auth/v1/verify"
}

variable "mailer_urlpaths_recovery" {
  description = "Mailer URL path for recovery"
  type        = string
  default     = "/auth/v1/verify"
}

variable "mailer_urlpaths_email_change" {
  description = "Mailer URL path for email change"
  type        = string
  default     = "/auth/v1/verify"
}

variable "enable_phone_signup" {
  description = "Enable phone signup"
  type        = bool
  default     = false
}

variable "enable_phone_autoconfirm" {
  description = "Enable phone autoconfirm"
  type        = bool
  default     = false
}

# --- PostgREST ---

variable "pgrst_db_schemas" {
  description = "PostgREST DB schemas"
  type        = string
  default     = "public,storage,graphql_public"
}

variable "pgrst_db_max_rows" {
  description = "Max rows returned by PostgREST"
  type        = number
  default     = 1000
}

variable "pgrst_db_extra_search_path" {
  description = "Extra schemas for PostgREST search_path"
  type        = string
  default     = "public"
}

# --- Storage ---

variable "spaces_access_key" {
  description = "DO Spaces access key ID"
  type        = string
  sensitive   = true
}

variable "spaces_secret_key" {
  description = "DO Spaces secret access key"
  type        = string
  sensitive   = true
}

variable "spaces_bucket" {
  description = "DO Spaces bucket name"
  type        = string
}

variable "spaces_region" {
  description = "DO Spaces region"
  type        = string
  default     = "fra1"
}

variable "spaces_endpoint" {
  description = "DO Spaces S3 endpoint"
  type        = string
  default     = "https://fra1.digitaloceanspaces.com"
}

variable "s3_protocol_access_key_id" {
  description = "Access key for S3 protocol endpoint"
  type        = string
  sensitive   = true
  default     = ""
}

variable "s3_protocol_access_key_secret" {
  description = "Secret key for S3 protocol endpoint"
  type        = string
  sensitive   = true
  default     = ""
}

# --- Edge Functions ---

variable "functions_verify_jwt" {
  description = "Verify JWT for edge functions"
  type        = bool
  default     = false
}
