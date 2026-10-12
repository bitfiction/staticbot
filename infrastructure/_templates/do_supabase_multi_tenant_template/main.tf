# Per-tenant Supabase module.
# Deploys a tenant's own Postgres plus Auth, PostgREST, Storage API, Edge
# Functions, Meta and an Envoy API gateway into a dedicated namespace
# (tenant-{id}). Realtime, Supavisor, ImgProxy and Analytics are shared and
# live in the shared namespace provisioned by
# staticbot-control-center/infra/digitalocean/modules-tenants/shared.
#
# This module does NOT create the cluster — it receives cluster credentials
# and shared service hostnames as input variables.

terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

provider "kubernetes" {
  host                   = var.cluster_endpoint
  token                  = var.cluster_token
  cluster_ca_certificate = base64decode(var.cluster_ca_certificate)
}

locals {
  tenant_namespace = "tenant-${var.tenant_id}"

  # Tenants start on Postgres 17. supabase-sync.py bumps this within the 17
  # track only; a new major needs an upgrade path (pg_upgrade) first, which the
  # check-postgres-major init container enforces.
  postgres_image = "supabase/postgres:17.6.1.136"
  postgres_major = split(".", split(":", local.postgres_image)[1])[0]

  # The tenant's own Postgres, reachable in-namespace as `db`
  db_host     = "db"
  db_fqdn     = "db.${local.tenant_namespace}.svc.cluster.local"
  db_port     = 5432
  db_name     = "postgres"
  db_uri_auth = "postgres://supabase_auth_admin:${var.postgres_password}@${local.db_host}:${local.db_port}/${local.db_name}"
  db_uri_rest = "postgres://authenticator:${var.postgres_password}@${local.db_host}:${local.db_port}/${local.db_name}"
  db_uri_stor = "postgres://supabase_storage_admin:${var.postgres_password}@${local.db_host}:${local.db_port}/${local.db_name}"
  db_uri_fn   = "postgresql://postgres:${var.postgres_password}@${local.db_host}:${local.db_port}/${local.db_name}"

  # Public API URL for this tenant; Auth's external URL carries the /auth/v1
  # prefix since self-hosted 0.7.0 (as on the platform).
  api_url          = "https://${var.tenant_id}.${var.api_domain}"
  api_external_url = "${local.api_url}/auth/v1"

  # In-namespace address of the tenant's API gateway, used by Edge Functions.
  internal_api_url = "http://api-gw:8000"

  realtime_host  = "realtime.${var.shared_namespace}.svc.cluster.local"
  supavisor_host = "supavisor.${var.shared_namespace}.svc.cluster.local"
  imgproxy_host  = "imgproxy.${var.shared_namespace}.svc.cluster.local"

  # WAL-G settings shared by the db container (archive_command) and the backup
  # sidecar. Secrets come from the tenant Secret, see local.walg_secret_env.
  walg_env = merge(
    {
      WALG_S3_PREFIX          = "s3://${var.backup_s3_bucket}/tenants/${var.tenant_id}"
      AWS_REGION              = var.backup_s3_region
      WALG_COMPRESSION_METHOD = "lz4"
    },
    var.backup_s3_endpoint == "" ? {} : {
      AWS_ENDPOINT            = var.backup_s3_endpoint
      AWS_S3_FORCE_PATH_STYLE = "true"
    }
  )
  walg_secret_env = {
    AWS_ACCESS_KEY_ID     = "BACKUP_S3_ACCESS_KEY_ID"
    AWS_SECRET_ACCESS_KEY = "BACKUP_S3_SECRET_ACCESS_KEY"
  }

  # Asymmetric JWT support is opt-in, like upstream's commented-out JWT_KEYS/JWT_JWKS.
  jwt_keys_enabled = nonsensitive(var.jwt_keys != "")
  jwt_jwks_enabled = nonsensitive(var.jwt_jwks != "")

  # Tenants get no Studio, but Envoy's config always protects the Studio routes
  # with basic auth. Use credentials nobody knows, derived from the JWT secret.
  dashboard_password = sha256("${var.jwt_secret}:staticbot-dashboard")
}
