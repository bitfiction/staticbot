resource "aws_ecs_service" "db" {
  name            = "db"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.db.arn
  desired_count   = 1
  launch_type     = "FARGATE"

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

resource "aws_ecs_task_definition" "db" {
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

  container_definitions = jsonencode([
    {
      name      = "db"
      image     = local.postgres_image
      essential = true
      portMappings = [
        {
          containerPort = 5432
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "POSTGRES_HOST", value = "/var/run/postgresql" },
        { name = "PGPORT", value = tostring(var.postgres_port) },
        { name = "POSTGRES_PORT", value = tostring(var.postgres_port) },
        { name = "PGPASSWORD", value = var.postgres_password },
        { name = "POSTGRES_PASSWORD", value = var.postgres_password },
        { name = "PGDATABASE", value = var.postgres_db },
        { name = "POSTGRES_DB", value = var.postgres_db },
        { name = "JWT_EXP", value = tostring(var.jwt_expiry) },
        # Init SQL content injection
        { name = "SQL_REALTIME", value = file("${path.module}/docker/volumes/db/realtime.sql") },
        { name = "SQL_WEBHOOKS", value = file("${path.module}/docker/volumes/db/webhooks.sql") },
        { name = "SQL_ROLES", value = file("${path.module}/docker/volumes/db/roles.sql") },
        { name = "SQL_JWT", value = file("${path.module}/docker/volumes/db/jwt.sql") },
        { name = "SQL_SUPABASE", value = file("${path.module}/docker/volumes/db/_supabase.sql") },
        { name = "SQL_LOGS", value = file("${path.module}/docker/volumes/db/logs.sql") },
        { name = "SQL_POOLER", value = file("${path.module}/docker/volumes/db/pooler.sql") }
      ]
      mountPoints = [
        {
          sourceVolume  = "db-data"
          containerPath = "/var/lib/postgresql/data"
          readOnly      = false
        },
        {
          sourceVolume  = "db-config"
          containerPath = "/mnt/postgresql-custom"
          readOnly      = false
        }
      ]
      # Write the init SQL next to the image's own init-scripts/ and migrations/
      # (as upstream's docker-compose.yml mounts them), persist
      # /etc/postgresql-custom on EFS (seeded from the image, existing entries
      # such as pgsodium_root.key kept), then start Postgres.
      command = [
        "bash", "-c",
        <<EOT
        set -e
        mkdir -p /docker-entrypoint-initdb.d/migrations /docker-entrypoint-initdb.d/init-scripts
        echo "$SQL_REALTIME" > /docker-entrypoint-initdb.d/migrations/99-realtime.sql
        echo "$SQL_WEBHOOKS" > /docker-entrypoint-initdb.d/init-scripts/98-webhooks.sql
        echo "$SQL_ROLES" > /docker-entrypoint-initdb.d/init-scripts/99-roles.sql
        echo "$SQL_JWT" > /docker-entrypoint-initdb.d/init-scripts/99-jwt.sql
        echo "$SQL_SUPABASE" > /docker-entrypoint-initdb.d/migrations/97-_supabase.sql
        echo "$SQL_LOGS" > /docker-entrypoint-initdb.d/migrations/99-logs.sql
        echo "$SQL_POOLER" > /docker-entrypoint-initdb.d/migrations/99-pooler.sql
        for f in /etc/postgresql-custom/*; do
          [ -e "/mnt/postgresql-custom/$(basename "$f")" ] || cp -a "$f" /mnt/postgresql-custom/
        done
        rm -rf /etc/postgresql-custom
        ln -s /mnt/postgresql-custom /etc/postgresql-custom
        exec docker-entrypoint.sh postgres -c config_file=/etc/postgresql/postgresql.conf -c log_min_messages=fatal
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
