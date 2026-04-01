resource "kubernetes_namespace" "supabase" {
  metadata {
    name = local.k8s_namespace
  }
}

# --- Kubernetes Secret: all sensitive Supabase configuration ---

resource "kubernetes_secret" "supabase_config" {
  metadata {
    name      = "supabase-config"
    namespace = kubernetes_namespace.supabase.metadata[0].name
  }

  data = {
    POSTGRES_PASSWORD              = var.postgres_password
    JWT_SECRET                     = var.jwt_secret
    ANON_KEY                       = var.anon_key
    SERVICE_ROLE_KEY               = var.service_role_key
    DASHBOARD_PASSWORD             = var.dashboard_password
    PG_META_CRYPTO_KEY             = var.pg_meta_crypto_key
    SECRET_KEY_BASE                = var.secret_key_base
    VAULT_ENC_KEY                  = var.vault_enc_key
    LOGFLARE_PUBLIC_ACCESS_TOKEN   = var.logflare_public_access_token
    LOGFLARE_PRIVATE_ACCESS_TOKEN  = var.logflare_private_access_token
    SUPABASE_PUBLISHABLE_KEY       = var.supabase_publishable_key
    SUPABASE_SECRET_KEY            = var.supabase_secret_key
    ANON_KEY_ASYMMETRIC            = var.anon_key_asymmetric
    SERVICE_ROLE_KEY_ASYMMETRIC    = var.service_role_key_asymmetric
    SMTP_PASS                      = var.smtp_pass != null ? var.smtp_pass : ""
    S3_PROTOCOL_ACCESS_KEY_ID      = var.s3_protocol_access_key_id
    S3_PROTOCOL_ACCESS_KEY_SECRET  = var.s3_protocol_access_key_secret
    OPENAI_API_KEY                 = var.openai_api_key
  }
}

# --- ConfigMap: DB init SQL scripts ---
# Mounted to /docker-entrypoint-initdb.d/ on the PostgreSQL container.
# Numeric prefixes control execution order.

resource "kubernetes_config_map" "db_init_scripts" {
  metadata {
    name      = "db-init-scripts"
    namespace = kubernetes_namespace.supabase.metadata[0].name
  }

  data = {
    "97-_supabase.sql" = file("${path.module}/docker/volumes/db/_supabase.sql")
    "98-webhooks.sql"  = file("${path.module}/docker/volumes/db/webhooks.sql")
    "99-roles.sql"     = file("${path.module}/docker/volumes/db/roles.sql")
    "99-jwt.sql"       = file("${path.module}/docker/volumes/db/jwt.sql")
    "99-realtime.sql"  = file("${path.module}/docker/volumes/db/realtime.sql")
    "99-logs.sql"      = file("${path.module}/docker/volumes/db/logs.sql")
    "99-pooler.sql"    = file("${path.module}/docker/volumes/db/pooler.sql")
  }
}

# --- ConfigMap: Kong API gateway config ---
# The kong.yml uses docker-compose service names which match K8s service names
# within the same namespace, except realtime which needs hostname replacement.

resource "kubernetes_config_map" "kong_config" {
  metadata {
    name      = "kong-config"
    namespace = kubernetes_namespace.supabase.metadata[0].name
  }

  data = {
    "kong.yml" = replace(
      file("${path.module}/docker/volumes/api/kong.yml"),
      "realtime-dev.supabase-realtime",
      "realtime"
    )
    "kong-entrypoint.sh" = file("${path.module}/docker/volumes/api/kong-entrypoint.sh")
  }
}

# --- ConfigMap: Supavisor pooler config ---

resource "kubernetes_config_map" "pooler_config" {
  metadata {
    name      = "pooler-config"
    namespace = kubernetes_namespace.supabase.metadata[0].name
  }

  data = {
    "pooler.exs" = file("${path.module}/docker/volumes/pooler/pooler.exs")
  }
}
