# --- Tenant Identity ---

variable "tenant_id" {
  description = "Unique tenant identifier (used in namespace, subdomain and as the Realtime/Supavisor tenant ID)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,40}[a-z0-9])?$", var.tenant_id))
    error_message = "tenant_id must be a DNS label: lowercase letters, digits and dashes, at most 42 characters."
  }
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

variable "shared_namespace" {
  description = "Kubernetes namespace of the shared services (Realtime, Supavisor, ImgProxy, Analytics)"
  type        = string
  default     = "supabase-shared"
}

variable "shared_api_jwt_secret" {
  description = "Secret the shared Realtime and Supavisor management APIs verify admin JWTs with (shared module output `shared_api_jwt_secret`)"
  type        = string
  sensitive   = true
}

variable "api_domain" {
  description = "Base API domain (e.g. sb.frever.net) — tenant gets {tenant_id}.{api_domain}"
  type        = string
}

# --- Database (tenant-owned Postgres) ---

variable "postgres_password" {
  description = "Password of this tenant's Postgres (postgres, supabase_admin and the service roles). Unique per tenant."
  type        = string
  sensitive   = true
}

variable "db_storage_size" {
  description = "Size of the tenant's Postgres volume"
  type        = string
  default     = "5Gi"
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

variable "jwt_keys" {
  description = "JSON array of signing JWKs for Auth (EC private + legacy symmetric). Leave empty to sign with the legacy HS256 secret only."
  type        = string
  sensitive   = true
  default     = ""
}

variable "jwt_jwks" {
  description = "Public JWKS JSON ({\"keys\":[...]}) PostgREST, Realtime, Storage and Edge Functions verify asymmetric JWTs with. Required when the opaque API keys are set."
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
  description = "Schemas exposed by PostgREST. Upstream stopped exposing the protected `storage` schema in self-hosted 0.7.0."
  type        = string
  default     = "public,graphql_public"
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

# --- Supavisor (shared pooler) ---

variable "pooler_default_pool_size" {
  description = "Supavisor pool size for this tenant"
  type        = number
  default     = 15
}

variable "pooler_max_client_conn" {
  description = "Maximum Supavisor client connections for this tenant"
  type        = number
  default     = 100
}

# --- Backups (WAL-G, like Staticbot's own database) ---
# Continuous WAL archiving plus a base backup every backup_interval_hours, to
# s3://{backup_s3_bucket}/tenants/{tenant_id}. See k8s/db-lifecycle/README.md.

variable "wal_g_image" {
  description = "Image carrying a static /wal-g (staticbot-control-center docker/wal-g), e.g. registry.digitalocean.com/staticbot-prod/wal-g:v3.0.9"
  type        = string
}

variable "image_pull_secret_name" {
  description = "Pull secret for wal_g_image in the tenant namespace. With DOCR registry integration on the cluster, DO injects one named after the registry (e.g. staticbot-prod) into every namespace. Empty for a public image."
  type        = string
  default     = ""
}

variable "backup_s3_bucket" {
  description = "Bucket holding all tenants' WAL-G archives (each under tenants/{tenant_id})"
  type        = string
}

variable "backup_s3_region" {
  description = "Region of the backup bucket"
  type        = string
}

variable "backup_s3_endpoint" {
  description = "S3 endpoint for a non-AWS store (e.g. https://fra1.digitaloceanspaces.com). Empty for AWS S3."
  type        = string
  default     = ""
}

variable "backup_s3_access_key_id" {
  description = "Access key with read/write/list on the backup bucket"
  type        = string
  sensitive   = true
}

variable "backup_s3_secret_access_key" {
  description = "Secret for backup_s3_access_key_id"
  type        = string
  sensitive   = true
}

variable "backup_interval_hours" {
  description = "Hours between base backups (WAL is archived continuously in between)"
  type        = number
  default     = 24
}

variable "backup_retain_full" {
  description = "Base backups to keep; older ones and their WAL are deleted"
  type        = number
  default     = 14
}
