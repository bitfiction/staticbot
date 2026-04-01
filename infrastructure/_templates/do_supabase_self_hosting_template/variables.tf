# --- DigitalOcean ---

variable "do_token" {
  description = "DigitalOcean API Token"
  type        = string
  sensitive   = true
}

variable "do_region" {
  description = "DigitalOcean region"
  type        = string
  default     = "fra1"
}

variable "project_name" {
  description = "Project name for tagging and naming resources"
  type        = string
  default     = "supabase-self-hosted"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.10.10.0/24"
}

# --- Kubernetes Cluster ---

variable "k8s_version" {
  description = "DOKS Kubernetes version"
  type        = string
  default     = "1.31.1-do.5"
}

variable "node_size" {
  description = "DOKS node size slug"
  type        = string
  default     = "s-4vcpu-8gb"
}

variable "node_min_count" {
  description = "Minimum number of nodes in the pool"
  type        = number
  default     = 1
}

variable "node_max_count" {
  description = "Maximum number of nodes in the pool"
  type        = number
  default     = 3
}

# --- Domain & TLS ---

variable "domain_name" {
  description = "Domain name for the Supabase instance (e.g. supabase.example.com)"
  type        = string
}

variable "letsencrypt_email" {
  description = "Email for Let's Encrypt certificate registration"
  type        = string
}

# --- Database ---

variable "postgres_port" {
  description = "Port for Postgres"
  type        = number
  default     = 5432
}

variable "postgres_db" {
  description = "Database name"
  type        = string
  default     = "postgres"
}

variable "postgres_password" {
  description = "Password for Postgres"
  type        = string
  sensitive   = true
}

variable "pg_meta_crypto_key" {
  description = "Crypto key for PG Meta"
  type        = string
  sensitive   = true
}

# --- Studio ---

variable "studio_default_organization" {
  description = "Default organization for Studio"
  type        = string
  default     = "Default Organization"
}

variable "studio_default_project" {
  description = "Default project for Studio"
  type        = string
  default     = "Default Project"
}

variable "openai_api_key" {
  description = "OpenAI API Key"
  type        = string
  sensitive   = true
  default     = ""
}

# --- Supabase Keys & URLs ---

variable "supabase_public_url" {
  description = "Public URL for Supabase (e.g. https://supabase.example.com)"
  type        = string
}

variable "anon_key" {
  description = "Anon Key"
  type        = string
  sensitive   = true
}

variable "service_role_key" {
  description = "Service Role Key"
  type        = string
  sensitive   = true
}

variable "jwt_secret" {
  description = "JWT Secret"
  type        = string
  sensitive   = true
}

variable "jwt_expiry" {
  description = "JWT Expiry in seconds"
  type        = number
  default     = 3600
}

# --- Opaque API Keys (ES256) ---

variable "supabase_publishable_key" {
  description = "Opaque API key for client-side use (anon role). Leave empty for legacy HS256-only."
  type        = string
  sensitive   = true
  default     = ""
}

variable "supabase_secret_key" {
  description = "Opaque API key for server-side use (service_role). Leave empty for legacy HS256-only."
  type        = string
  sensitive   = true
  default     = ""
}

variable "anon_key_asymmetric" {
  description = "Pre-signed ES256 JWT for anon role."
  type        = string
  sensitive   = true
  default     = ""
}

variable "service_role_key_asymmetric" {
  description = "Pre-signed ES256 JWT for service_role."
  type        = string
  sensitive   = true
  default     = ""
}

# --- Analytics (Logflare) ---

variable "logflare_public_access_token" {
  description = "Logflare Public Access Token"
  type        = string
  sensitive   = true
}

variable "logflare_private_access_token" {
  description = "Logflare Private Access Token"
  type        = string
  sensitive   = true
}

# --- Kong ---

variable "kong_http_port" {
  description = "Kong HTTP Port"
  type        = number
  default     = 8000
}

variable "kong_https_port" {
  description = "Kong HTTPS Port"
  type        = number
  default     = 8443
}

variable "dashboard_username" {
  description = "Dashboard Username"
  type        = string
  default     = "supabase"
}

variable "dashboard_password" {
  description = "Dashboard Password"
  type        = string
  sensitive   = true
}

# --- Auth (GoTrue) ---

variable "api_external_url" {
  description = "API External URL"
  type        = string
}

variable "site_url" {
  description = "Site URL"
  type        = string
}

variable "additional_redirect_urls" {
  description = "Additional Redirect URLs (comma separated)"
  type        = string
  default     = ""
}

variable "disable_signup" {
  description = "Disable Signup"
  type        = bool
  default     = false
}

variable "enable_email_signup" {
  description = "Enable Email Signup"
  type        = bool
  default     = true
}

variable "enable_anonymous_users" {
  description = "Enable Anonymous Users"
  type        = bool
  default     = false
}

variable "enable_email_autoconfirm" {
  description = "Enable Email Autoconfirm"
  type        = bool
  default     = false
}

variable "smtp_admin_email" {
  description = "SMTP Admin Email"
  type        = string
}

variable "smtp_host" {
  description = "SMTP Host"
  type        = string
}

variable "smtp_port" {
  description = "SMTP Port"
  type        = number
  default     = 587
}

variable "smtp_user" {
  description = "SMTP User"
  type        = string
  default     = null
}

variable "smtp_pass" {
  description = "SMTP Password"
  type        = string
  sensitive   = true
  default     = null
}

variable "smtp_sender_name" {
  description = "SMTP Sender Name"
  type        = string
  default     = "Supabase"
}

variable "mailer_urlpaths_invite" {
  description = "Mailer URL Path Invite"
  type        = string
  default     = "/auth/v1/verify"
}

variable "mailer_urlpaths_confirmation" {
  description = "Mailer URL Path Confirmation"
  type        = string
  default     = "/auth/v1/verify"
}

variable "mailer_urlpaths_recovery" {
  description = "Mailer URL Path Recovery"
  type        = string
  default     = "/auth/v1/verify"
}

variable "mailer_urlpaths_email_change" {
  description = "Mailer URL Path Email Change"
  type        = string
  default     = "/auth/v1/verify"
}

variable "enable_phone_signup" {
  description = "Enable Phone Signup"
  type        = bool
  default     = false
}

variable "enable_phone_autoconfirm" {
  description = "Enable Phone Autoconfirm"
  type        = bool
  default     = false
}

# --- Rest (PostgREST) ---

variable "pgrst_db_schemas" {
  description = "PostgREST DB Schemas"
  type        = string
  default     = "public,storage,graphql_public"
}

variable "pgrst_db_max_rows" {
  description = "Max number of rows returned by a PostgREST request"
  type        = number
  default     = 1000
}

variable "pgrst_db_extra_search_path" {
  description = "Extra schemas added to PostgREST search_path"
  type        = string
  default     = "public"
}

# --- Realtime ---

variable "secret_key_base" {
  description = "Secret Key Base"
  type        = string
  sensitive   = true
}

# --- ImgProxy ---

variable "imgproxy_enable_webp_detection" {
  description = "Enable WebP Detection"
  type        = bool
  default     = true
}

# --- Storage ---

variable "storage_s3_bucket" {
  description = "S3 bucket name (or directory name when using file backend)"
  type        = string
  default     = "stub"
}

variable "storage_tenant_id" {
  description = "Storage tenant ID"
  type        = string
  default     = "stub"
}

variable "storage_region" {
  description = "Storage region"
  type        = string
  default     = "stub"
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

# --- Functions ---

variable "functions_verify_jwt" {
  description = "Verify JWT for Functions"
  type        = bool
  default     = false
}

# --- Supavisor (Pooler) ---

variable "pooler_proxy_port_transaction" {
  description = "Pooler Proxy Port Transaction"
  type        = number
  default     = 6543
}

variable "vault_enc_key" {
  description = "Vault Encryption Key"
  type        = string
  sensitive   = true
}

variable "pooler_tenant_id" {
  description = "Pooler Tenant ID"
  type        = string
  default     = "main"
}

variable "pooler_default_pool_size" {
  description = "Pooler Default Pool Size"
  type        = number
  default     = 20
}

variable "pooler_max_client_conn" {
  description = "Pooler Max Client Connections"
  type        = number
  default     = 100
}

variable "pooler_db_pool_size" {
  description = "Pooler DB Pool Size"
  type        = number
  default     = 60
}
