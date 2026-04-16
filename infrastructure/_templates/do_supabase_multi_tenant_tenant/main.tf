# Per-tenant Supabase module.
# Deploys GoTrue, PostgREST, Storage API, and Edge Functions into a
# dedicated namespace (tenant-{id}), connecting to shared infrastructure
# provisioned by do_supabase_multi_tenant_shared.
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
  # DB connection strings pointing to the tenant's database on the shared Postgres
  db_uri_auth    = "postgres://supabase_auth_admin:${var.postgres_password}@${var.shared_db_host}:${var.shared_db_port}/tenant_${var.tenant_id}"
  db_uri_rest    = "postgres://authenticator:${var.postgres_password}@${var.shared_db_host}:${var.shared_db_port}/tenant_${var.tenant_id}"
  db_uri_storage = "postgres://supabase_storage_admin:${var.postgres_password}@${var.shared_db_host}:${var.shared_db_port}/tenant_${var.tenant_id}"
  db_uri_funcs   = "postgresql://postgres:${var.postgres_password}@${var.shared_db_host}:${var.shared_db_port}/tenant_${var.tenant_id}"
  # Public API URL for this tenant
  api_url = "https://${var.tenant_id}.${var.api_domain}"
}
