# --- Kong ---

resource "aws_ecs_service" "kong" {
  name            = "kong"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.kong.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.kong.arn
    container_name   = "kong"
    container_port   = 8000
  }

  service_registries {
    registry_arn = aws_service_discovery_service.kong.arn
  }
}

resource "aws_service_discovery_service" "kong" {
  name = "kong"
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id
    dns_records {
      ttl  = 10
      type = "A"
    }
  }
}

resource "aws_ecs_task_definition" "kong" {
  family                   = "${local.sanitized_name}-kong"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.execution_role.arn
  task_role_arn            = aws_iam_role.task_role.arn

  container_definitions = jsonencode([
    {
      name      = "kong"
      image     = "kong/kong:3.9.1"
      essential = true
      portMappings = [
        {
          containerPort = 8000
          protocol      = "tcp"
        },
        {
          containerPort = 8443
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "KONG_DATABASE", value = "off" },
        { name = "KONG_DECLARATIVE_CONFIG", value = "/usr/local/kong/kong.yml" },
        { name = "KONG_DNS_ORDER", value = "LAST,A,CNAME" },
        { name = "KONG_DNS_NOT_FOUND_TTL", value = "1" },
        { name = "KONG_PLUGINS", value = "request-transformer,cors,key-auth,acl,basic-auth,request-termination,ip-restriction,post-function" },
        { name = "KONG_NGINX_PROXY_PROXY_BUFFER_SIZE", value = "160k" },
        { name = "KONG_NGINX_PROXY_PROXY_BUFFERS", value = "64 160k" },
        { name = "KONG_PROXY_ACCESS_LOG", value = "/dev/stdout combined" },
        { name = "SUPABASE_ANON_KEY", value = var.anon_key },
        { name = "SUPABASE_SERVICE_KEY", value = var.service_role_key },
        { name = "SUPABASE_PUBLISHABLE_KEY", value = var.supabase_publishable_key },
        { name = "SUPABASE_SECRET_KEY", value = var.supabase_secret_key },
        { name = "ANON_KEY_ASYMMETRIC", value = var.anon_key_asymmetric },
        { name = "SERVICE_ROLE_KEY_ASYMMETRIC", value = var.service_role_key_asymmetric },
        { name = "DASHBOARD_USERNAME", value = var.dashboard_username },
        { name = "DASHBOARD_PASSWORD", value = var.dashboard_password },
        # Inject modified config and entrypoint
        { name = "KONG_CONFIG_TEMPLATE", value = replace(file("${path.module}/docker/volumes/api/kong.yml"), "realtime-dev.supabase-realtime", "realtime.supabase.internal") },
        { name = "KONG_ENTRYPOINT_SCRIPT", value = file("${path.module}/docker/volumes/api/kong-entrypoint.sh") }
      ]
      command = [
        "bash", "-c",
        "echo \"$KONG_ENTRYPOINT_SCRIPT\" > /home/kong/kong-entrypoint.sh && chmod +x /home/kong/kong-entrypoint.sh && echo \"$KONG_CONFIG_TEMPLATE\" > /home/kong/temp.yml && /home/kong/kong-entrypoint.sh"
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.main.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "kong"
        }
      }
      healthCheck = {
        command = ["CMD-SHELL", "kong health"]
        interval = 10
        timeout = 10
        retries = 3
      }
    }
  ])
}

# --- Studio ---

resource "aws_ecs_service" "studio" {
  name            = "studio"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.studio.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.studio.arn
    container_name   = "studio"
    container_port   = 3000
  }

  service_registries {
    registry_arn = aws_service_discovery_service.studio.arn
  }
}

resource "aws_service_discovery_service" "studio" {
  name = "studio"
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id
    dns_records {
      ttl  = 10
      type = "A"
    }
  }
}

resource "aws_ecs_task_definition" "studio" {
  family                   = "${local.sanitized_name}-studio"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.execution_role.arn
  task_role_arn            = aws_iam_role.task_role.arn

  container_definitions = jsonencode([
    {
      name      = "studio"
      image     = "supabase/studio:2026.03.16-sha-5528817"
      essential = true
      portMappings = [
        {
          containerPort = 3000
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "HOSTNAME", value = "::" },
        { name = "STUDIO_PG_META_URL", value = "http://meta.supabase.internal:8080" },
        { name = "POSTGRES_PORT", value = tostring(var.postgres_port) },
        { name = "POSTGRES_HOST", value = "db.supabase.internal" },
        { name = "POSTGRES_DB", value = var.postgres_db },
        { name = "POSTGRES_PASSWORD", value = var.postgres_password },
        { name = "PG_META_CRYPTO_KEY", value = var.pg_meta_crypto_key },
        { name = "PGRST_DB_SCHEMAS", value = var.pgrst_db_schemas },
        { name = "PGRST_DB_MAX_ROWS", value = tostring(var.pgrst_db_max_rows) },
        { name = "PGRST_DB_EXTRA_SEARCH_PATH", value = var.pgrst_db_extra_search_path },
        { name = "DEFAULT_ORGANIZATION_NAME", value = var.studio_default_organization },
        { name = "DEFAULT_PROJECT_NAME", value = var.studio_default_project },
        { name = "OPENAI_API_KEY", value = var.openai_api_key },
        { name = "SUPABASE_URL", value = "http://kong.supabase.internal:8000" },
        { name = "SUPABASE_PUBLIC_URL", value = var.supabase_public_url },
        { name = "SUPABASE_ANON_KEY", value = var.anon_key },
        { name = "SUPABASE_SERVICE_KEY", value = var.service_role_key },
        { name = "AUTH_JWT_SECRET", value = var.jwt_secret },
        { name = "LOGFLARE_API_KEY", value = var.logflare_public_access_token },
        { name = "LOGFLARE_PUBLIC_ACCESS_TOKEN", value = var.logflare_public_access_token },
        { name = "LOGFLARE_PRIVATE_ACCESS_TOKEN", value = var.logflare_private_access_token },
        { name = "LOGFLARE_URL", value = "http://analytics.supabase.internal:4000" },
        { name = "NEXT_PUBLIC_ENABLE_LOGS", value = "true" },
        { name = "NEXT_ANALYTICS_BACKEND_PROVIDER", value = "postgres" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.main.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "studio"
        }
      }
    }
  ])
}

# --- Meta ---

resource "aws_ecs_service" "meta" {
  name            = "meta"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.meta.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.meta.arn
  }
}

resource "aws_service_discovery_service" "meta" {
  name = "meta"
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id
    dns_records {
      ttl  = 10
      type = "A"
    }
  }
}

resource "aws_ecs_task_definition" "meta" {
  family                   = "${local.sanitized_name}-meta"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.execution_role.arn
  task_role_arn            = aws_iam_role.task_role.arn

  container_definitions = jsonencode([
    {
      name      = "meta"
      image     = "supabase/postgres-meta:v0.95.2"
      essential = true
      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "PG_META_PORT", value = "8080" },
        { name = "PG_META_DB_HOST", value = "db.supabase.internal" },
        { name = "PG_META_DB_PORT", value = tostring(var.postgres_port) },
        { name = "PG_META_DB_NAME", value = var.postgres_db },
        { name = "PG_META_DB_USER", value = "supabase_admin" },
        { name = "PG_META_DB_PASSWORD", value = var.postgres_password },
        { name = "CRYPTO_KEY", value = var.pg_meta_crypto_key }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.main.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "meta"
        }
      }
    }
  ])
}

# --- Analytics (Logflare) ---

resource "aws_ecs_service" "analytics" {
  name            = "analytics"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.analytics.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.analytics.arn
  }
}

resource "aws_service_discovery_service" "analytics" {
  name = "analytics"
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id
    dns_records {
      ttl  = 10
      type = "A"
    }
  }
}

resource "aws_ecs_task_definition" "analytics" {
  family                   = "${local.sanitized_name}-analytics"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.execution_role.arn
  task_role_arn            = aws_iam_role.task_role.arn

  container_definitions = jsonencode([
    {
      name      = "analytics"
      image     = "supabase/logflare:1.31.2"
      essential = true
      portMappings = [
        {
          containerPort = 4000
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "LOGFLARE_NODE_HOST", value = "127.0.0.1" },
        { name = "DB_USERNAME", value = "supabase_admin" },
        { name = "DB_DATABASE", value = "_supabase" },
        { name = "DB_HOSTNAME", value = "db.supabase.internal" },
        { name = "DB_PORT", value = tostring(var.postgres_port) },
        { name = "DB_PASSWORD", value = var.postgres_password },
        { name = "DB_SCHEMA", value = "_analytics" },
        { name = "LOGFLARE_PUBLIC_ACCESS_TOKEN", value = var.logflare_public_access_token },
        { name = "LOGFLARE_PRIVATE_ACCESS_TOKEN", value = var.logflare_private_access_token },
        { name = "LOGFLARE_SINGLE_TENANT", value = "true" },
        { name = "LOGFLARE_SUPABASE_MODE", value = "true" },
        { name = "POSTGRES_BACKEND_URL", value = "postgresql://supabase_admin:${var.postgres_password}@db.supabase.internal:${var.postgres_port}/_supabase" },
        { name = "POSTGRES_BACKEND_SCHEMA", value = "_analytics" },
        { name = "LOGFLARE_FEATURE_FLAG_OVERRIDE", value = "multibackend=true" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.main.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "analytics"
        }
      }
      healthCheck = {
        command = ["CMD", "curl", "http://localhost:4000/health"]
        interval = 5
        timeout = 5
        retries = 10
      }
    }
  ])
}

# --- Functions ---

resource "aws_ecs_service" "functions" {
  name            = "functions"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.functions.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.functions.arn
  }
}

resource "aws_service_discovery_service" "functions" {
  name = "functions"
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id
    dns_records {
      ttl  = 10
      type = "A"
    }
  }
}

resource "aws_ecs_task_definition" "functions" {
  family                   = "${local.sanitized_name}-functions"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.execution_role.arn
  task_role_arn            = aws_iam_role.task_role.arn

  volume {
    name = "functions-data"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.main.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.functions.id
        iam             = "ENABLED"
      }
    }
  }

  container_definitions = jsonencode([
    {
      name      = "functions"
      image     = "supabase/edge-runtime:v1.71.2"
      essential = true
      portMappings = [
        {
          containerPort = 9000
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "JWT_SECRET", value = var.jwt_secret },
        { name = "SUPABASE_URL", value = "http://kong.supabase.internal:8000" },
        { name = "SUPABASE_PUBLIC_URL", value = var.supabase_public_url },
        { name = "SUPABASE_ANON_KEY", value = var.anon_key },
        { name = "SUPABASE_SERVICE_ROLE_KEY", value = var.service_role_key },
        { name = "SUPABASE_PUBLISHABLE_KEYS", value = "{\"default\":\"${var.supabase_publishable_key}\"}" },
        { name = "SUPABASE_SECRET_KEYS", value = "{\"default\":\"${var.supabase_secret_key}\"}" },
        { name = "SUPABASE_DB_URL", value = "postgresql://postgres:${var.postgres_password}@db.supabase.internal:${var.postgres_port}/${var.postgres_db}" },
        { name = "VERIFY_JWT", value = tostring(var.functions_verify_jwt) }
      ]
      mountPoints = [
        {
          sourceVolume  = "functions-data"
          containerPath = "/home/deno/functions"
          readOnly      = false
        }
      ]
      command = ["start", "--main-service", "/home/deno/functions/main"]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.main.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "functions"
        }
      }
    }
  ])
}

# --- Supavisor ---

resource "aws_ecs_service" "supavisor" {
  name            = "supavisor"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.supavisor.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.supavisor.arn
  }
}

resource "aws_service_discovery_service" "supavisor" {
  name = "supavisor"
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id
    dns_records {
      ttl  = 10
      type = "A"
    }
  }
}

resource "aws_ecs_task_definition" "supavisor" {
  family                   = "${local.sanitized_name}-supavisor"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.execution_role.arn
  task_role_arn            = aws_iam_role.task_role.arn

  container_definitions = jsonencode([
    {
      name      = "supavisor"
      image     = "supabase/supavisor:2.7.4"
      essential = true
      portMappings = [
        {
          containerPort = 5432
          protocol      = "tcp"
        },
        {
          containerPort = 6543
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "PORT", value = "4000" },
        { name = "POSTGRES_PORT", value = tostring(var.postgres_port) },
        { name = "POSTGRES_DB", value = var.postgres_db },
        { name = "POSTGRES_PASSWORD", value = var.postgres_password },
        { name = "DATABASE_URL", value = "ecto://supabase_admin:${var.postgres_password}@db.supabase.internal:${var.postgres_port}/_supabase" },
        { name = "CLUSTER_POSTGRES", value = "true" },
        { name = "SECRET_KEY_BASE", value = var.secret_key_base },
        { name = "VAULT_ENC_KEY", value = var.vault_enc_key },
        { name = "API_JWT_SECRET", value = var.jwt_secret },
        { name = "METRICS_JWT_SECRET", value = var.jwt_secret },
        { name = "REGION", value = "local" },
        { name = "ERL_AFLAGS", value = "-proto_dist inet_tcp" },
        { name = "POOLER_TENANT_ID", value = var.pooler_tenant_id },
        { name = "POOLER_DEFAULT_POOL_SIZE", value = tostring(var.pooler_default_pool_size) },
        { name = "POOLER_MAX_CLIENT_CONN", value = tostring(var.pooler_max_client_conn) },
        { name = "POOLER_POOL_MODE", value = "transaction" },
        { name = "DB_POOL_SIZE", value = tostring(var.pooler_db_pool_size) },
        # Inject config
        { name = "POOLER_CONFIG", value = file("${path.module}/docker/volumes/pooler/pooler.exs") }
      ]
      command = [
        "/bin/sh", "-c",
        "mkdir -p /etc/pooler && echo \"$POOLER_CONFIG\" > /etc/pooler/pooler.exs && /app/bin/migrate && /app/bin/supavisor eval \"$$(cat /etc/pooler/pooler.exs)\" && /app/bin/server"
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.main.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "supavisor"
        }
      }
      healthCheck = {
        command = ["CMD", "curl", "-sSfL", "--head", "-o", "/dev/null", "http://127.0.0.1:4000/api/health"]
        interval = 10
        timeout = 5
        retries = 5
      }
    }
  ])
}
