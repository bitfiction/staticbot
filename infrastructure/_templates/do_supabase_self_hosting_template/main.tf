terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.10"
    }
  }
}

provider "digitalocean" {
  token = var.do_token
  # Spaces keys let the provider create the backup bucket (backups.tf)
  spaces_access_id  = var.spaces_access_id
  spaces_secret_key = var.spaces_secret_key
}

provider "kubernetes" {
  host                   = digitalocean_kubernetes_cluster.main.endpoint
  token                  = digitalocean_kubernetes_cluster.main.kube_config[0].token
  cluster_ca_certificate = base64decode(digitalocean_kubernetes_cluster.main.kube_config[0].cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = digitalocean_kubernetes_cluster.main.endpoint
    token                  = digitalocean_kubernetes_cluster.main.kube_config[0].token
    cluster_ca_certificate = base64decode(digitalocean_kubernetes_cluster.main.kube_config[0].cluster_ca_certificate)
  }
}

locals {
  sanitized_name = replace(replace(var.project_name, "/--+/", "-"), "/-$/", "")
  k8s_namespace  = "supabase"

  # Postgres 17 only. supabase-sync.py bumps this within the 17 track; a new
  # major needs a pg_upgrade step first, which check-postgres-major enforces.
  postgres_image = "supabase/postgres:17.6.1.136"
  postgres_major = split(".", split(":", local.postgres_image)[1])[0]

  # Since self-hosted 0.7.0 API_EXTERNAL_URL includes the /auth/v1 prefix (as on
  # the platform). Accept the bare form too, so older tfvars keep working.
  api_external_url_base = trimsuffix(coalesce(var.api_external_url, var.supabase_public_url), "/")
  api_external_url      = endswith(local.api_external_url_base, "/auth/v1") ? local.api_external_url_base : "${local.api_external_url_base}/auth/v1"

  # In-cluster address of the API gateway, used by Studio and Edge Functions.
  internal_api_url = "http://api-gw:8000"

  # WAL-G settings shared by the db container (archive_command), the backup
  # sidecar and restores. Keys come from the Secret, see local.walg_secret_env.
  walg_env = {
    WALG_S3_PREFIX          = "s3://${digitalocean_spaces_bucket.pg_backups.name}/postgres"
    AWS_REGION              = var.do_region
    AWS_ENDPOINT            = "https://${var.do_region}.digitaloceanspaces.com"
    AWS_S3_FORCE_PATH_STYLE = "true"
    WALG_COMPRESSION_METHOD = "lz4"
  }
  walg_secret_env = {
    AWS_ACCESS_KEY_ID     = "BACKUP_S3_ACCESS_KEY_ID"
    AWS_SECRET_ACCESS_KEY = "BACKUP_S3_SECRET_ACCESS_KEY"
  }

  # Asymmetric JWT support is opt-in, like upstream's commented-out JWT_KEYS/JWT_JWKS.
  jwt_keys_enabled = nonsensitive(var.jwt_keys != "")
  jwt_jwks_enabled = nonsensitive(var.jwt_jwks != "")
}
