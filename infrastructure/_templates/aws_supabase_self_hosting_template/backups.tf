# --- Backup target: an S3 bucket in this account ---
# Same setup as Staticbot's own database backups (versioned, encrypted, public
# access blocked, stale multipart uploads aborted) with an IAM user scoped to
# this bucket only.

resource "aws_s3_bucket" "pg_backups" {
  bucket = coalesce(var.backup_bucket_name, "${local.sanitized_name}-pg-backups")
}

resource "aws_s3_bucket_versioning" "pg_backups" {
  bucket = aws_s3_bucket.pg_backups.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "pg_backups" {
  bucket = aws_s3_bucket.pg_backups.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "pg_backups" {
  bucket                  = aws_s3_bucket.pg_backups.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "pg_backups" {
  bucket = aws_s3_bucket.pg_backups.id

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # Versioning keeps what `wal-g delete` removes; expire it so retention frees space.
  rule {
    id     = "expire-deleted-backups"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

resource "aws_iam_user" "pg_backup" {
  name = "${local.iam_name}-pg-backup"
}

resource "aws_iam_user_policy" "pg_backup" {
  name = "s3-backup-access"
  user = aws_iam_user.pg_backup.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          # WAL-G uploads base backups via S3 multipart
          "s3:AbortMultipartUpload",
          "s3:ListBucketMultipartUploads",
          "s3:ListMultipartUploadParts"
        ]
        Resource = [
          aws_s3_bucket.pg_backups.arn,
          "${aws_s3_bucket.pg_backups.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_access_key" "pg_backup" {
  user = aws_iam_user.pg_backup.name
}
