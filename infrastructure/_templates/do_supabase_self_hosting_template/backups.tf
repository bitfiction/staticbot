# --- Backup target: a Spaces bucket in this account ---
# Mirrors the S3 setup of Staticbot's own database (versioned, private, stale
# multipart uploads aborted) with a key scoped to this bucket only, so WAL-G
# can't touch anything else in the account.

resource "digitalocean_spaces_bucket" "pg_backups" {
  name   = coalesce(var.backup_bucket_name, "${local.sanitized_name}-pg-backups")
  region = var.do_region
  acl    = "private"

  versioning {
    enabled = true
  }

  lifecycle_rule {
    id                                     = "abort-incomplete-multipart-uploads"
    enabled                                = true
    abort_incomplete_multipart_upload_days = 7
  }

  # Versioning keeps what `wal-g delete` removes; expire it so retention frees space.
  lifecycle_rule {
    id      = "expire-deleted-backups"
    enabled = true

    noncurrent_version_expiration {
      days = 7
    }
  }
}

resource "digitalocean_spaces_key" "pg_backup" {
  name = "${local.sanitized_name}-pg-backup"

  grant {
    bucket     = digitalocean_spaces_bucket.pg_backups.name
    permission = "readwrite"
  }
}
