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

  # Postgres 17 only. supabase-sync.py bumps this within the 17 track; a new
  # major needs a pg_upgrade step first, which check-postgres-major enforces.
  postgres_image = "supabase/postgres:17.6.1.136"
  postgres_major = split(".", split(":", local.postgres_image)[1])[0]

  # The image's postgres user. EFS access points force their POSIX identity on
  # every file operation, and Postgres refuses a data directory it doesn't own.
  postgres_posix_id = { uid = 100, gid = 101 }

  # Since self-hosted 0.7.0 API_EXTERNAL_URL includes the /auth/v1 prefix (as on
  # the platform). Accept the bare form too, so older tfvars keep working.
  api_external_url_base = trimsuffix(coalesce(var.api_external_url, var.supabase_public_url), "/")
  api_external_url      = endswith(local.api_external_url_base, "/auth/v1") ? local.api_external_url_base : "${local.api_external_url_base}/auth/v1"

  # Services reach each other through Cloud Map (<name>.supabase.internal).
  internal_api_url = "http://api-gw.supabase.internal:8000"

  # PostgREST accepts a symmetric secret or a JWKS; prefer the JWKS when set.
  pgrst_jwt_secret = var.jwt_jwks != "" ? var.jwt_jwks : var.jwt_secret

  # WAL-G settings for archive_command, the backup sidecar and restores
  walg_env = [
    { name = "WALG_S3_PREFIX", value = "s3://${aws_s3_bucket.pg_backups.bucket}/postgres" },
    { name = "AWS_REGION", value = var.aws_region },
    { name = "WALG_COMPRESSION_METHOD", value = "lz4" },
    { name = "AWS_ACCESS_KEY_ID", value = aws_iam_access_key.pg_backup.id },
    { name = "AWS_SECRET_ACCESS_KEY", value = aws_iam_access_key.pg_backup.secret },
  ]

  # Optional env entries for asymmetric JWTs, like upstream's commented-out
  # JWT_KEYS/JWT_JWKS lines.
  jwt_keys_env = nonsensitive(var.jwt_keys != "") ? [{ name = "GOTRUE_JWT_KEYS", value = var.jwt_keys }] : []
  jwks_env     = nonsensitive(var.jwt_jwks != "")
}
