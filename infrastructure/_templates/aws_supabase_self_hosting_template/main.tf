terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  assume_role {
    role_arn    = var.terraform_role_arn
    external_id = var.external_id
  }

  default_tags {
    tags = {
      Project   = var.project_name
      Terraform = "true"
    }
  }
}

locals {
  # Sanitize project name: collapse multiple hyphens, strip trailing hyphens
  sanitized_name = replace(replace(var.project_name, "/--+/", "-"), "/-$/", "")

  # Truncated names for resources with strict AWS length limits
  # ALB target groups: max 32 chars, IAM roles/policies: max 64 chars
  short_name = replace(substr(local.sanitized_name, 0, 22), "/-$/", "")
  iam_name   = replace(substr(local.sanitized_name, 0, 48), "/-$/", "")

  # One image per supported Postgres major. A PG15 data directory can't be
  # opened by PG17: upgrade in place with docker/utils/upgrade-pg17.sh first.
  postgres_images = {
    "15" = "supabase/postgres:15.8.1.085"
    "17" = "supabase/postgres:17.6.1.136"
  }
  postgres_image = local.postgres_images[var.postgres_version]

  # The postgres user's uid/gid differ between the PG15 and PG17 images. EFS
  # access points force their POSIX identity on every file operation, and
  # Postgres refuses a data directory it doesn't own, so they must match.
  postgres_posix_ids = {
    "15" = { uid = 105, gid = 106 }
    "17" = { uid = 100, gid = 101 }
  }
  postgres_posix_id = local.postgres_posix_ids[var.postgres_version]

  # Since self-hosted 0.7.0 API_EXTERNAL_URL includes the /auth/v1 prefix (as on
  # the platform). Accept the bare form too, so older tfvars keep working.
  api_external_url_base = trimsuffix(coalesce(var.api_external_url, var.supabase_public_url), "/")
  api_external_url      = endswith(local.api_external_url_base, "/auth/v1") ? local.api_external_url_base : "${local.api_external_url_base}/auth/v1"

  # Services reach each other through Cloud Map (<name>.supabase.internal).
  internal_api_url = "http://api-gw.supabase.internal:8000"

  # PostgREST accepts a symmetric secret or a JWKS; prefer the JWKS when set.
  pgrst_jwt_secret = var.jwt_jwks != "" ? var.jwt_jwks : var.jwt_secret

  # Optional env entries for asymmetric JWTs, like upstream's commented-out
  # JWT_KEYS/JWT_JWKS lines.
  jwt_keys_env = nonsensitive(var.jwt_keys != "") ? [{ name = "GOTRUE_JWT_KEYS", value = var.jwt_keys }] : []
  jwks_env     = nonsensitive(var.jwt_jwks != "")
}
