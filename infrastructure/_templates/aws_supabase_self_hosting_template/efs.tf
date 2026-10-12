resource "aws_efs_file_system" "main" {
  creation_token = "${local.sanitized_name}-efs"
  encrypted      = true

  tags = {
    Name = "${local.sanitized_name}-efs"
  }
}

resource "aws_efs_mount_target" "private" {
  count           = 2
  file_system_id  = aws_efs_file_system.main.id
  subnet_id       = aws_subnet.private[count.index].id
  security_groups = [aws_security_group.efs.id]
}

# --- Access Points ---

# Postgres data directory. The POSIX identity must be the image's postgres
# user (it differs between PG15 and PG17), and Postgres requires 0700.
resource "aws_efs_access_point" "db" {
  file_system_id = aws_efs_file_system.main.id
  posix_user {
    gid = local.postgres_posix_id.gid
    uid = local.postgres_posix_id.uid
  }
  root_directory {
    path = "/db"
    creation_info {
      owner_gid   = local.postgres_posix_id.gid
      owner_uid   = local.postgres_posix_id.uid
      permissions = "700"
    }
  }

  tags = {
    Name = "${local.sanitized_name}-db-ap"
  }
}

resource "aws_efs_access_point" "storage" {
  file_system_id = aws_efs_file_system.main.id
  posix_user {
    gid = 1000
    uid = 1000
  }
  root_directory {
    path = "/storage"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "755"
    }
  }

  tags = {
    Name = "${local.sanitized_name}-storage-ap"
  }
}

resource "aws_efs_access_point" "functions" {
  file_system_id = aws_efs_file_system.main.id
  posix_user {
    gid = 1000
    uid = 1000
  }
  root_directory {
    path = "/functions"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "755"
    }
  }

  tags = {
    Name = "${local.sanitized_name}-functions-ap"
  }
}

resource "aws_efs_access_point" "config" {
  file_system_id = aws_efs_file_system.main.id
  posix_user {
    gid = 0
    uid = 0
  }
  root_directory {
    path = "/config"
    creation_info {
      owner_gid   = 0
      owner_uid   = 0
      permissions = "755"
    }
  }

  tags = {
    Name = "${local.sanitized_name}-config-ap"
  }
}

# /etc/postgresql-custom: config the image's postgresql.conf includes, plus the
# pgsodium/Vault root key. Seeded from the image on first boot; losing it makes
# Vault secrets undecryptable.
resource "aws_efs_access_point" "db_config" {
  file_system_id = aws_efs_file_system.main.id
  posix_user {
    gid = local.postgres_posix_id.gid
    uid = local.postgres_posix_id.uid
  }
  root_directory {
    path = "/db-config"
    creation_info {
      owner_gid   = local.postgres_posix_id.gid
      owner_uid   = local.postgres_posix_id.uid
      permissions = "700"
    }
  }

  tags = {
    Name = "${local.sanitized_name}-db-config-ap"
  }
}

# Studio's local SQL snippets (SNIPPETS_MANAGEMENT_FOLDER)
resource "aws_efs_access_point" "studio_snippets" {
  file_system_id = aws_efs_file_system.main.id
  posix_user {
    gid = 1000
    uid = 1000
  }
  root_directory {
    path = "/studio-snippets"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "755"
    }
  }

  tags = {
    Name = "${local.sanitized_name}-studio-snippets-ap"
  }
}
