resource "aws_ecs_service" "db" {
  name            = "db"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.db.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  # Stop the old task before starting the new one. ECS's default rolling update
  # would briefly run two Postgres on the same EFS data directory (postmaster.pid
  # can't see another task's process) and two archivers on one WAL-G prefix.
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.db.arn
  }
}

resource "aws_service_discovery_service" "db" {
  name = "db"
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id
    dns_records {
      ttl  = 10
      type = "A"
    }
  }
}

# --- Database lifecycle files (db-lifecycle/, a copy of _shared/supabase-db-lifecycle) ---
# Shipped to the task as gzip+base64 env (an ECS task definition is capped at
# 64 KB) and unpacked by the prepare container into shared task volumes.

locals {
  db_lifecycle_dir = "${path.module}/db-lifecycle"

  # Upstream init SQL: name in /initsql → path under /docker-entrypoint-initdb.d/,
  # as in upstream docker-compose.yml
  db_init_sql = {
    "97-_supabase.sql" = { path = "migrations/97-_supabase.sql", source = "_supabase.sql" }
    "98-webhooks.sql"  = { path = "init-scripts/98-webhooks.sql", source = "webhooks.sql" }
    "99-roles.sql"     = { path = "init-scripts/99-roles.sql", source = "roles.sql" }
    "99-jwt.sql"       = { path = "init-scripts/99-jwt.sql", source = "jwt.sql" }
    "99-realtime.sql"  = { path = "migrations/99-realtime.sql", source = "realtime.sql" }
    "99-logs.sql"      = { path = "migrations/99-logs.sql", source = "logs.sql" }
    "99-pooler.sql"    = { path = "migrations/99-pooler.sql", source = "pooler.sql" }
  }

  db_template_migrations = {
    for f in fileset("${local.db_lifecycle_dir}/migrations", "*.sql") :
    f => file("${local.db_lifecycle_dir}/migrations/${f}")
  }

  db_lifecycle_files = merge({
    "_schema.sql"          = file("${local.db_lifecycle_dir}/_schema.sql")
    "baseline.sh"          = file("${local.db_lifecycle_dir}/baseline.sh")
    "migrate.sh"           = file("${local.db_lifecycle_dir}/migrate.sh")
    "backup.sh"            = file("${local.db_lifecycle_dir}/backup.sh")
    "restore.sh"           = file("${local.db_lifecycle_dir}/restore.sh")
    "image-migrations.txt" = file("${local.db_lifecycle_dir}/image-migrations.txt")
    "init-mounts.txt"      = join("", [for k, v in local.db_init_sql : "${k} ${v.path}\n"])
  }, local.db_template_migrations)

  # "<name> <base64gzip> <name> <base64gzip> ...", unpacked by the prepare container
  db_lifecycle_bundle = join(" ", [for k, v in local.db_lifecycle_files : "${k} ${base64gzip(v)}"])
  db_init_sql_bundle  = join(" ", [for k, v in local.db_init_sql : "${k} ${base64gzip(file("${path.module}/docker/volumes/db/${v.source}"))}"])

  # Copies WAL-G and unpacks both bundles; runs first in the db and db-restore tasks
  db_prepare_container = {
    name      = "prepare"
    image     = var.wal_g_image
    essential = false
    environment = [
      { name = "STATICBOT_FILES", value = local.db_lifecycle_bundle },
      { name = "INIT_SQL_FILES", value = local.db_init_sql_bundle }
    ]
    command = [
      "sh", "-c",
      <<-EOT
      set -e
      cp /wal-g /walg/wal-g
      unpack() {
        dir=$1; shift
        while [ $# -gt 0 ]; do
          mkdir -p "$(dirname "$dir/$1")"
          echo "$2" | base64 -d | gunzip > "$dir/$1"
          shift 2
        done
      }
      unpack /staticbot $STATICBOT_FILES
      unpack /initsql $INIT_SQL_FILES
      chmod 755 /staticbot/*.sh
      EOT
    ]
    mountPoints = [
      { sourceVolume = "walg", containerPath = "/walg", readOnly = false },
      { sourceVolume = "staticbot", containerPath = "/staticbot", readOnly = false },
      { sourceVolume = "initsql", containerPath = "/initsql", readOnly = false }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.main.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "db-prepare"
      }
    }
  }
}

resource "aws_ecs_task_definition" "db" {
  lifecycle {
    precondition {
      # migrate.sh applies them in name order; the bundle splits on spaces
      condition     = alltrue([for f in keys(local.db_template_migrations) : can(regex("^[0-9]{14}_[a-z0-9_]+\\.sql$", f))])
      error_message = "db-lifecycle/migrations/*.sql must be named <14-digit timestamp>_<snake_case>.sql."
    }
  }

  family                   = "${local.sanitized_name}-db"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 1024
  memory                   = 2048
  execution_role_arn       = aws_iam_role.execution_role.arn
  task_role_arn            = aws_iam_role.task_role.arn

  volume {
    name = "db-data"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.main.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.db.id
        iam             = "ENABLED"
      }
    }
  }

  volume {
    name = "db-config"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.main.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.db_config.id
        iam             = "ENABLED"
      }
    }
  }

  volume {
    name = "db-backup-state"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.main.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.db_backup_state.id
        iam             = "ENABLED"
      }
    }
  }

  # Task-local scratch volumes shared between the containers
  volume {
    name = "walg"
  }
  volume {
    name = "staticbot"
  }
  volume {
    name = "initsql"
  }

  container_definitions = jsonencode([
    local.db_prepare_container,
    {
      name      = "db"
      image     = local.postgres_image
      essential = true
      dependsOn = [{ containerName = "prepare", condition = "SUCCESS" }]
      portMappings = [
        {
          containerPort = 5432
          protocol      = "tcp"
        }
      ]
      environment = concat([
        { name = "POSTGRES_HOST", value = "/var/run/postgresql" },
        { name = "PGPORT", value = tostring(var.postgres_port) },
        { name = "POSTGRES_PORT", value = tostring(var.postgres_port) },
        { name = "PGPASSWORD", value = var.postgres_password },
        { name = "POSTGRES_PASSWORD", value = var.postgres_password },
        { name = "PGDATABASE", value = var.postgres_db },
        { name = "POSTGRES_DB", value = var.postgres_db },
        { name = "JWT_EXP", value = tostring(var.jwt_expiry) },
        # Recorded by the baseline hook as the image that initialised the database
        { name = "STATICBOT_IMAGE", value = local.postgres_image }
      ], local.walg_env)
      mountPoints = [
        { sourceVolume = "db-data", containerPath = "/var/lib/postgresql/data", readOnly = false },
        { sourceVolume = "db-config", containerPath = "/mnt/postgresql-custom", readOnly = false },
        { sourceVolume = "walg", containerPath = "/walg", readOnly = true },
        { sourceVolume = "staticbot", containerPath = "/staticbot", readOnly = true },
        { sourceVolume = "initsql", containerPath = "/initsql", readOnly = true }
      ]
      # 1. Refuse another Postgres major's data. 2. Put the init SQL and the
      # baseline hook next to the image's own init-scripts/ and migrations/.
      # 3. Persist /etc/postgresql-custom on EFS (seeded from the image,
      # existing entries such as pgsodium_root.key kept). 4. Start Postgres with
      # continuous WAL archiving, as on Staticbot's own database.
      command = [
        "bash", "-c",
        <<EOT
        set -e
        if [ -f /var/lib/postgresql/data/PG_VERSION ] && [ "$(cat /var/lib/postgresql/data/PG_VERSION)" != "${local.postgres_major}" ]; then
          echo "PGDATA holds Postgres $(cat /var/lib/postgresql/data/PG_VERSION) data but the image is Postgres ${local.postgres_major}: upgrade the data (pg_upgrade) before switching majors"
          exit 1
        fi
        while read -r key path; do
          mkdir -p "$(dirname "/docker-entrypoint-initdb.d/$path")"
          cp "/initsql/$key" "/docker-entrypoint-initdb.d/$path"
        done < /staticbot/init-mounts.txt
        cp /staticbot/baseline.sh /docker-entrypoint-initdb.d/zz-staticbot-baseline.sh
        chmod 755 /docker-entrypoint-initdb.d/zz-staticbot-baseline.sh
        for f in /etc/postgresql-custom/*; do
          [ -e "/mnt/postgresql-custom/$(basename "$f")" ] || cp -a "$f" /mnt/postgresql-custom/
        done
        rm -rf /etc/postgresql-custom
        ln -s /mnt/postgresql-custom /etc/postgresql-custom
        exec docker-entrypoint.sh postgres -c config_file=/etc/postgresql/postgresql.conf -c log_min_messages=fatal \
          -c archive_mode=on -c "archive_command=/walg/wal-g wal-push %p" -c archive_timeout=60
        EOT
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.main.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "db"
        }
      }
      healthCheck = {
        command     = ["CMD", "pg_isready", "-U", "postgres", "-h", "localhost"]
        interval    = 5
        timeout     = 5
        retries     = 10
        startPeriod = 300
      }
    },
    # Base backups, retention and the Vault key (db-lifecycle/backup.sh)
    {
      name       = "backup"
      image      = local.postgres_image
      essential  = false
      dependsOn  = [{ containerName = "db", condition = "HEALTHY" }]
      entryPoint = ["bash"]
      command    = ["/staticbot/backup.sh"]
      environment = concat([
        { name = "PGPASSWORD", value = var.postgres_password },
        { name = "PGPORT", value = tostring(var.postgres_port) },
        { name = "BACKUP_INTERVAL_HOURS", value = tostring(var.backup_interval_hours) },
        { name = "BACKUP_RETAIN_FULL", value = tostring(var.backup_retain_full) }
      ], local.walg_env)
      mountPoints = [
        { sourceVolume = "db-data", containerPath = "/var/lib/postgresql/data", readOnly = false },
        { sourceVolume = "db-config", containerPath = "/etc/postgresql-custom", readOnly = true },
        { sourceVolume = "db-backup-state", containerPath = "/var/lib/postgresql/backup-state", readOnly = false },
        { sourceVolume = "walg", containerPath = "/walg", readOnly = true },
        { sourceVolume = "staticbot", containerPath = "/staticbot", readOnly = true }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.main.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "db-backup"
        }
      }
    },
    # Schema upgrades after an image or template change (db-lifecycle/migrate.sh).
    # Runs once per task start and exits; a no-op when nothing is pending.
    {
      name       = "migrate"
      image      = local.postgres_image
      essential  = false
      dependsOn  = [{ containerName = "db", condition = "HEALTHY" }]
      entryPoint = ["bash"]
      command    = ["/staticbot/migrate.sh"]
      environment = [
        { name = "PGHOST", value = "127.0.0.1" },
        { name = "PGPORT", value = tostring(var.postgres_port) },
        { name = "PGDATABASE", value = var.postgres_db },
        { name = "PGPASSWORD", value = var.postgres_password },
        { name = "STATICBOT_IMAGE", value = local.postgres_image }
      ]
      mountPoints = [
        { sourceVolume = "staticbot", containerPath = "/staticbot", readOnly = true },
        { sourceVolume = "initsql", containerPath = "/initsql", readOnly = true }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.main.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "db-migrate"
        }
      }
    }
  ])
}

# --- Point-in-time restore ---
# Not a service: run it with `aws ecs run-task` while the db service is scaled
# to 0 (README.md).

resource "aws_ecs_task_definition" "db_restore" {
  family                   = "${local.sanitized_name}-db-restore"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 1024
  memory                   = 2048
  execution_role_arn       = aws_iam_role.execution_role.arn
  task_role_arn            = aws_iam_role.task_role.arn

  # The file system root without an access point, so restore.sh acts as root
  # (it renames /db and creates files for the postgres user).
  volume {
    name = "efs-root"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.main.id
      root_directory     = "/"
      transit_encryption = "ENABLED"
    }
  }
  volume {
    name = "walg"
  }
  volume {
    name = "staticbot"
  }
  volume {
    name = "initsql"
  }

  container_definitions = jsonencode([
    local.db_prepare_container,
    {
      name       = "restore"
      image      = local.postgres_image
      essential  = true
      dependsOn  = [{ containerName = "prepare", condition = "SUCCESS" }]
      entryPoint = ["bash"]
      command    = ["/staticbot/restore.sh"]
      environment = concat([
        # Override at run-task time; empty restores everything archived
        { name = "RECOVERY_TARGET_TIME", value = "" },
        { name = "DATA_SUBDIR", value = "db" },
        { name = "CUSTOM_SUBDIR", value = "db-config" },
        { name = "STATE_SUBDIR", value = "db-backup-state" }
      ], local.walg_env)
      mountPoints = [
        { sourceVolume = "efs-root", containerPath = "/pvc", readOnly = false },
        { sourceVolume = "walg", containerPath = "/walg", readOnly = true },
        { sourceVolume = "staticbot", containerPath = "/staticbot", readOnly = true }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.main.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "db-restore"
        }
      }
    }
  ])
}

# --- Vector ---
# Upstream's vector.yml collects Docker container logs, which Fargate doesn't
# expose, so on AWS logs only reach CloudWatch (the Logs Explorer stays empty).
# Shipping them to Logflare needs FireLens or a CloudWatch subscription.

resource "aws_ecs_service" "vector" {
  name            = "vector"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.vector.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.vector.arn
  }
}

resource "aws_service_discovery_service" "vector" {
  name = "vector"
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id
    dns_records {
      ttl  = 10
      type = "A"
    }
  }
}

resource "aws_ecs_task_definition" "vector" {
  family                   = "${local.sanitized_name}-vector"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.execution_role.arn
  task_role_arn            = aws_iam_role.task_role.arn

  container_definitions = jsonencode([
    {
      name      = "vector"
      image     = "timberio/vector:0.53.0-alpine"
      essential = true
      environment = [
        { name = "LOGFLARE_PUBLIC_ACCESS_TOKEN", value = var.logflare_public_access_token },
        { name = "VECTOR_CONFIG", value = file("${path.module}/docker/volumes/logs/vector.yml") }
      ]
      command = [
        "sh", "-c",
        "echo \"$VECTOR_CONFIG\" > /etc/vector/vector.yml && vector --config /etc/vector/vector.yml"
      ]
      # Note: Vector 0.53.0 also supports --config flag directly
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.main.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "vector"
        }
      }
      healthCheck = {
        command  = ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:9001/health"]
        interval = 5
        timeout  = 5
        retries  = 3
      }
    }
  ])
}
