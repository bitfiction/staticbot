# --- Auth (GoTrue) ---

resource "aws_ecs_service" "auth" {
  name            = "auth"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.auth.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.auth.arn
  }
}

resource "aws_service_discovery_service" "auth" {
  name = "auth"
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id
    dns_records {
      ttl  = 10
      type = "A"
    }
  }
}

resource "aws_ecs_task_definition" "auth" {
  family                   = "${var.project_name}-auth"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.execution_role.arn
  task_role_arn            = aws_iam_role.task_role.arn

  container_definitions = jsonencode([
    {
      name      = "auth"
      image     = "supabase/gotrue:v2.186.0"
      essential = true
      portMappings = [
        {
          containerPort = 9999
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "GOTRUE_API_HOST", value = "0.0.0.0" },
        { name = "GOTRUE_API_PORT", value = "9999" },
        { name = "API_EXTERNAL_URL", value = var.api_external_url },
        { name = "GOTRUE_DB_DRIVER", value = "postgres" },
        { name = "GOTRUE_DB_DATABASE_URL", value = "postgres://supabase_auth_admin:${var.postgres_password}@db.supabase.internal:${var.postgres_port}/${var.postgres_db}" }, # using internal DNS
        { name = "GOTRUE_SITE_URL", value = var.site_url },
        { name = "GOTRUE_URI_ALLOW_LIST", value = var.additional_redirect_urls },
        { name = "GOTRUE_DISABLE_SIGNUP", value = tostring(var.disable_signup) },
        { name = "GOTRUE_JWT_ADMIN_ROLES", value = "service_role" },
        { name = "GOTRUE_JWT_AUD", value = "authenticated" },
        { name = "GOTRUE_JWT_DEFAULT_GROUP_NAME", value = "authenticated" },
        { name = "GOTRUE_JWT_EXP", value = tostring(var.jwt_expiry) },
        { name = "GOTRUE_JWT_SECRET", value = var.jwt_secret },
        { name = "GOTRUE_EXTERNAL_EMAIL_ENABLED", value = tostring(var.enable_email_signup) },
        { name = "GOTRUE_EXTERNAL_ANONYMOUS_USERS_ENABLED", value = tostring(var.enable_anonymous_users) },
        { name = "GOTRUE_MAILER_AUTOCONFIRM", value = tostring(var.enable_email_autoconfirm) },
        { name = "GOTRUE_SMTP_ADMIN_EMAIL", value = var.smtp_admin_email },
        { name = "GOTRUE_SMTP_HOST", value = var.smtp_host },
        { name = "GOTRUE_SMTP_PORT", value = tostring(var.smtp_port) },
        { name = "GOTRUE_SMTP_USER", value = var.smtp_user },
        { name = "GOTRUE_SMTP_PASS", value = var.smtp_pass },
        { name = "GOTRUE_SMTP_SENDER_NAME", value = var.smtp_sender_name },
        { name = "GOTRUE_MAILER_URLPATHS_INVITE", value = var.mailer_urlpaths_invite },
        { name = "GOTRUE_MAILER_URLPATHS_CONFIRMATION", value = var.mailer_urlpaths_confirmation },
        { name = "GOTRUE_MAILER_URLPATHS_RECOVERY", value = var.mailer_urlpaths_recovery },
        { name = "GOTRUE_MAILER_URLPATHS_EMAIL_CHANGE", value = var.mailer_urlpaths_email_change },
        { name = "GOTRUE_EXTERNAL_PHONE_ENABLED", value = tostring(var.enable_phone_signup) },
        { name = "GOTRUE_SMS_AUTOCONFIRM", value = tostring(var.enable_phone_autoconfirm) }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.main.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "auth"
        }
      }
      healthCheck = {
        command = ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:9999/health"]
        interval = 5
        timeout = 5
        retries = 3
      }
    }
  ])
}

# --- Rest (PostgREST) ---

resource "aws_ecs_service" "rest" {
  name            = "rest"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.rest.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.rest.arn
  }
}

resource "aws_service_discovery_service" "rest" {
  name = "rest"
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id
    dns_records {
      ttl  = 10
      type = "A"
    }
  }
}

resource "aws_ecs_task_definition" "rest" {
  family                   = "${var.project_name}-rest"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.execution_role.arn
  task_role_arn            = aws_iam_role.task_role.arn

  container_definitions = jsonencode([
    {
      name      = "rest"
      image     = "postgrest/postgrest:v14.6"
      essential = true
      portMappings = [
        {
          containerPort = 3000
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "PGRST_DB_URI", value = "postgres://authenticator:${var.postgres_password}@db.supabase.internal:${var.postgres_port}/${var.postgres_db}" },
        { name = "PGRST_DB_SCHEMAS", value = var.pgrst_db_schemas },
        { name = "PGRST_DB_MAX_ROWS", value = tostring(var.pgrst_db_max_rows) },
        { name = "PGRST_DB_EXTRA_SEARCH_PATH", value = var.pgrst_db_extra_search_path },
        { name = "PGRST_DB_ANON_ROLE", value = "anon" },
        { name = "PGRST_JWT_SECRET", value = var.jwt_secret },
        { name = "PGRST_DB_USE_LEGACY_GUCS", value = "false" },
        { name = "PGRST_APP_SETTINGS_JWT_SECRET", value = var.jwt_secret },
        { name = "PGRST_APP_SETTINGS_JWT_EXP", value = tostring(var.jwt_expiry) }
      ]
      command = ["postgrest"]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.main.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "rest"
        }
      }
    }
  ])
}

# --- Realtime ---

resource "aws_ecs_service" "realtime" {
  name            = "realtime"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.realtime.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.realtime.arn
  }
}

resource "aws_service_discovery_service" "realtime" {
  name = "realtime" # In compose: realtime-dev.supabase-realtime (container name), but here dns is 'realtime'
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id
    dns_records {
      ttl  = 10
      type = "A"
    }
  }
}

resource "aws_ecs_task_definition" "realtime" {
  family                   = "${var.project_name}-realtime"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.execution_role.arn
  task_role_arn            = aws_iam_role.task_role.arn

  container_definitions = jsonencode([
    {
      name      = "realtime"
      image     = "supabase/realtime:v2.76.5"
      essential = true
      portMappings = [
        {
          containerPort = 4000
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "PORT", value = "4000" },
        { name = "DB_HOST", value = "db.supabase.internal" },
        { name = "DB_PORT", value = tostring(var.postgres_port) },
        { name = "DB_USER", value = "supabase_admin" },
        { name = "DB_PASSWORD", value = var.postgres_password },
        { name = "DB_NAME", value = var.postgres_db },
        { name = "DB_AFTER_CONNECT_QUERY", value = "SET search_path TO _realtime" },
        { name = "DB_ENC_KEY", value = "supabaserealtime" },
        { name = "API_JWT_SECRET", value = var.jwt_secret },
        { name = "SECRET_KEY_BASE", value = var.secret_key_base },
        { name = "METRICS_JWT_SECRET", value = var.jwt_secret },
        { name = "ERL_AFLAGS", value = "-proto_dist inet_tcp" },
        { name = "DNS_NODES", value = "''" },
        { name = "RLIMIT_NOFILE", value = "10000" },
        { name = "APP_NAME", value = "realtime" },
        { name = "SEED_SELF_HOST", value = "true" },
        { name = "RUN_JANITOR", value = "true" },
        { name = "DISABLE_HEALTHCHECK_LOGGING", value = "true" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.main.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "realtime"
        }
      }
      healthCheck = {
        command = ["CMD-SHELL", "curl -sSfL --head -o /dev/null -H \"Authorization: Bearer ${var.anon_key}\" http://localhost:4000/api/tenants/realtime-dev/health"]
        interval = 30
        timeout = 5
        retries = 3
        startPeriod = 10
      }
    }
  ])
}

# --- Storage & Imgproxy ---

resource "aws_ecs_service" "storage" {
  name            = "storage"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.storage.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.storage.arn
  }
}

resource "aws_service_discovery_service" "storage" {
  name = "storage"
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id
    dns_records {
      ttl  = 10
      type = "A"
    }
  }
}

resource "aws_ecs_service" "imgproxy" {
  name            = "imgproxy"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.imgproxy.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.imgproxy.arn
  }
}

resource "aws_service_discovery_service" "imgproxy" {
  name = "imgproxy"
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id
    dns_records {
      ttl  = 10
      type = "A"
    }
  }
}

resource "aws_ecs_task_definition" "storage" {
  family                   = "${var.project_name}-storage"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.execution_role.arn
  task_role_arn            = aws_iam_role.task_role.arn

  volume {
    name = "storage-data"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.main.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.storage.id
        iam             = "ENABLED"
      }
    }
  }

  container_definitions = jsonencode([
    {
      name      = "storage"
      image     = "supabase/storage-api:v1.44.2"
      essential = true
      portMappings = [
        {
          containerPort = 5000
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "ANON_KEY", value = var.anon_key },
        { name = "SERVICE_KEY", value = var.service_role_key },
        { name = "POSTGREST_URL", value = "http://rest.supabase.internal:3000" },
        { name = "AUTH_JWT_SECRET", value = var.jwt_secret },
        { name = "DATABASE_URL", value = "postgres://supabase_storage_admin:${var.postgres_password}@db.supabase.internal:${var.postgres_port}/${var.postgres_db}" },
        { name = "STORAGE_PUBLIC_URL", value = var.supabase_public_url },
        { name = "REQUEST_ALLOW_X_FORWARDED_PATH", value = "true" },
        { name = "FILE_SIZE_LIMIT", value = "52428800" },
        { name = "STORAGE_BACKEND", value = "file" },
        { name = "GLOBAL_S3_BUCKET", value = var.storage_s3_bucket },
        { name = "FILE_STORAGE_BACKEND_PATH", value = "/var/lib/storage" },
        { name = "TENANT_ID", value = var.storage_tenant_id },
        { name = "REGION", value = var.storage_region },
        { name = "ENABLE_IMAGE_TRANSFORMATION", value = "true" },
        { name = "IMGPROXY_URL", value = "http://imgproxy.supabase.internal:5001" },
        { name = "S3_PROTOCOL_ACCESS_KEY_ID", value = var.s3_protocol_access_key_id },
        { name = "S3_PROTOCOL_ACCESS_KEY_SECRET", value = var.s3_protocol_access_key_secret }
      ]
      mountPoints = [
        {
          sourceVolume  = "storage-data"
          containerPath = "/var/lib/storage"
          readOnly      = false
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.main.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "storage"
        }
      }
      healthCheck = {
        command = ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:5000/status"]
        interval = 5
        timeout = 5
        retries = 3
      }
    }
  ])
}

resource "aws_ecs_task_definition" "imgproxy" {
  family                   = "${var.project_name}-imgproxy"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.execution_role.arn
  task_role_arn            = aws_iam_role.task_role.arn

  volume {
    name = "storage-data"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.main.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.storage.id
        iam             = "ENABLED"
      }
    }
  }

  container_definitions = jsonencode([
    {
      name      = "imgproxy"
      image     = "darthsim/imgproxy:v3.30.1"
      essential = true
      portMappings = [
        {
          containerPort = 5001
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "IMGPROXY_BIND", value = ":5001" },
        { name = "IMGPROXY_LOCAL_FILESYSTEM_ROOT", value = "/" },
        { name = "IMGPROXY_USE_ETAG", value = "true" },
        { name = "IMGPROXY_AUTO_WEBP", value = tostring(var.imgproxy_enable_webp_detection) },
        { name = "IMGPROXY_MAX_SRC_RESOLUTION", value = "16.8" }
      ]
      mountPoints = [
        {
          sourceVolume  = "storage-data"
          containerPath = "/var/lib/storage"
          readOnly      = false
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.main.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "imgproxy"
        }
      }
      healthCheck = {
        command = ["CMD", "imgproxy", "health"]
        interval = 5
        timeout = 5
        retries = 3
      }
    }
  ])
}
