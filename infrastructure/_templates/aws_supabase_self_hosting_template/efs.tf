resource "aws_efs_file_system" "main" {
  creation_token = "${var.project_name}-efs"
  encrypted      = true

  tags = {
    Name = "${var.project_name}-efs"
  }
}

resource "aws_efs_mount_target" "private" {
  count           = 2
  file_system_id  = aws_efs_file_system.main.id
  subnet_id       = aws_subnet.private[count.index].id
  security_groups = [aws_security_group.efs.id]
}

# --- Access Points ---

resource "aws_efs_access_point" "db" {
  file_system_id = aws_efs_file_system.main.id
  posix_user {
    gid = 999
    uid = 999
  }
  root_directory {
    path = "/db"
    creation_info {
      owner_gid   = 999
      owner_uid   = 999
      permissions = "755"
    }
  }

  tags = {
    Name = "${var.project_name}-db-ap"
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
    Name = "${var.project_name}-storage-ap"
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
    Name = "${var.project_name}-functions-ap"
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
    Name = "${var.project_name}-config-ap"
  }
}
