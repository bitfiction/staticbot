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

  # One image per supported Postgres major. A PG15 data directory can't be
  # opened by PG17: upgrade in place with docker/utils/upgrade-pg17.sh first.
  postgres_images = {
    "15" = "supabase/postgres:15.8.1.085"
    "17" = "supabase/postgres:17.6.1.136"
  }
  postgres_image = local.postgres_images[var.postgres_version]

  # Since self-hosted 0.7.0 API_EXTERNAL_URL includes the /auth/v1 prefix (as on
  # the platform). Accept the bare form too, so older tfvars keep working.
  api_external_url_base = trimsuffix(coalesce(var.api_external_url, var.supabase_public_url), "/")
  api_external_url      = endswith(local.api_external_url_base, "/auth/v1") ? local.api_external_url_base : "${local.api_external_url_base}/auth/v1"

  # In-cluster address of the API gateway, used by Studio and Edge Functions.
  internal_api_url = "http://api-gw:8000"

  # Asymmetric JWT support is opt-in, like upstream's commented-out JWT_KEYS/JWT_JWKS.
  jwt_keys_enabled = nonsensitive(var.jwt_keys != "")
  jwt_jwks_enabled = nonsensitive(var.jwt_jwks != "")
}
