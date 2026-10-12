# --- API Gateway (Envoy) ---
# Upstream's default gateway since self-hosted 0.8.0 (Kong is deprecated).
# The config files are shipped gzip+base64 in env vars (lds.template.yaml alone
# is ~55 KB; an ECS task definition is capped at 64 KB) and decoded on start.
# Cluster addresses use Cloud Map names, since tasks can't resolve bare
# service names; the Realtime Host header rewrite stays upstream's, because
# Realtime derives its tenant ID ("realtime-dev") from it.

locals {
  envoy_cds = replace(
    replace(
      file("${path.module}/docker/volumes/api/envoy/cds.yaml"),
      "address: realtime-dev.supabase-realtime",
      "address: realtime.supabase.internal"
    ),
    "/(?m)address: (auth|rest|storage|functions|meta|studio)$/",
    "address: $1.supabase.internal"
  )
}

resource "aws_ecs_service" "api_gw" {
  name            = "api-gw"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.api_gw.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api_gw.arn
    container_name   = "api-gw"
    container_port   = 8000
  }

  service_registries {
    registry_arn = aws_service_discovery_service.api_gw.arn
  }

  depends_on = [aws_lb_listener.http]
}

resource "aws_service_discovery_service" "api_gw" {
  name = "api-gw"
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id
    dns_records {
      ttl  = 10
      type = "A"
    }
  }
}

resource "aws_ecs_task_definition" "api_gw" {
  family                   = "${local.sanitized_name}-api-gw"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.execution_role.arn
  task_role_arn            = aws_iam_role.task_role.arn

  container_definitions = jsonencode([
    {
      name      = "api-gw"
      image     = "envoyproxy/envoy:v1.39.1"
      essential = true
      portMappings = [
        {
          containerPort = 8000
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "ANON_KEY", value = var.anon_key },
        { name = "SERVICE_ROLE_KEY", value = var.service_role_key },
        { name = "SUPABASE_PUBLISHABLE_KEY", value = var.supabase_publishable_key },
        { name = "SUPABASE_SECRET_KEY", value = var.supabase_secret_key },
        { name = "ANON_KEY_ASYMMETRIC", value = var.anon_key_asymmetric },
        { name = "SERVICE_ROLE_KEY_ASYMMETRIC", value = var.service_role_key_asymmetric },
        { name = "SUPABASE_PUBLIC_URL", value = var.supabase_public_url },
        { name = "DASHBOARD_USERNAME", value = var.dashboard_username },
        { name = "DASHBOARD_PASSWORD", value = var.dashboard_password },
        { name = "ENVOY_YAML_GZ", value = base64gzip(file("${path.module}/docker/volumes/api/envoy/envoy.yaml")) },
        { name = "ENVOY_CDS_GZ", value = base64gzip(local.envoy_cds) },
        { name = "ENVOY_LDS_TEMPLATE_GZ", value = base64gzip(file("${path.module}/docker/volumes/api/envoy/lds.template.yaml")) },
        { name = "ENVOY_ENTRYPOINT_GZ", value = base64gzip(file("${path.module}/docker/volumes/api/envoy/docker-entrypoint.sh")) }
      ]
      entryPoint = ["/bin/sh", "-c"]
      command = [
        <<-EOT
        set -e
        echo "$ENVOY_YAML_GZ" | base64 -d | gunzip > /etc/envoy/envoy.yaml
        echo "$ENVOY_CDS_GZ" | base64 -d | gunzip > /etc/envoy/cds.yaml
        echo "$ENVOY_LDS_TEMPLATE_GZ" | base64 -d | gunzip > /etc/envoy/lds.template.yaml
        echo "$ENVOY_ENTRYPOINT_GZ" | base64 -d | gunzip > /docker-entrypoint.sh
        exec /bin/sh /docker-entrypoint.sh
        EOT
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.main.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "api-gw"
        }
      }
      # TCP check, as upstream: the image has no curl or wget
      healthCheck = {
        command  = ["CMD-SHELL", "timeout 1 bash -c '</dev/tcp/127.0.0.1/8000'"]
        interval = 10
        timeout  = 5
        retries  = 3
      }
    }
  ])
}

# --- Studio ---
# Reached through the API gateway (basic auth), like upstream.

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
  memory                   = 1024
  execution_role_arn       = aws_iam_role.execution_role.arn
  task_role_arn            = aws_iam_role.task_role.arn

  volume {
    name = "studio-snippets"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.main.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.studio_snippets.id
        iam             = "ENABLED"
      }
    }
  }

  container_definitions = jsonencode([
    {
      name      = "studio"
      image     = "supabase/studio:2026.09.07-sha-7996410"
      essential = true
      portMappings = [
        {
          containerPort = 3000
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "HOSTNAME", value = "0.0.0.0" },
        { name = "STUDIO_PG_META_URL", value = "http://meta.supabase.internal:8080" },
        { name = "POSTGRES_PORT", value = tostring(var.postgres_port) },
        { name = "POSTGRES_HOST", value = "db.supabase.internal" },
        { name = "POSTGRES_DB", value = var.postgres_db },
        { name = "POSTGRES_PASSWORD", value = var.postgres_password },
        # See: https://supabase.com/docs/guides/self-hosting/remove-superuser-access
        { name = "POSTGRES_USER_READ_WRITE", value = "postgres" },
        { name = "PG_META_CRYPTO_KEY", value = var.pg_meta_crypto_key },
        { name = "PGRST_DB_SCHEMAS", value = var.pgrst_db_schemas },
        { name = "PGRST_DB_MAX_ROWS", value = tostring(var.pgrst_db_max_rows) },
        { name = "PGRST_DB_EXTRA_SEARCH_PATH", value = var.pgrst_db_extra_search_path },
        { name = "DEFAULT_ORGANIZATION_NAME", value = var.studio_default_organization },
        { name = "DEFAULT_PROJECT_NAME", value = var.studio_default_project },
        { name = "OPENAI_API_KEY", value = var.openai_api_key },
        { name = "SUPABASE_URL", value = local.internal_api_url },
        { name = "SUPABASE_PUBLIC_URL", value = var.supabase_public_url },
        { name = "SUPABASE_ANON_KEY", value = var.anon_key },
        { name = "SUPABASE_SERVICE_KEY", value = var.service_role_key },
        { name = "AUTH_JWT_SECRET", value = var.jwt_secret },
        { name = "SUPABASE_PUBLISHABLE_KEY", value = var.supabase_publishable_key },
        { name = "SUPABASE_SECRET_KEY", value = var.supabase_secret_key },
        # Logs Explorer, as in upstream docker-compose.logs.yml
        { name = "LOGFLARE_PRIVATE_ACCESS_TOKEN", value = var.logflare_private_access_token },
        { name = "LOGFLARE_URL", value = "http://analytics.supabase.internal:4000" },
        { name = "ENABLED_FEATURES_LOGS_ALL", value = "true" },
        { name = "SNIPPETS_MANAGEMENT_FOLDER", value = "/app/snippets" }
      ]
      mountPoints = [
        {
          sourceVolume  = "studio-snippets"
          containerPath = "/app/snippets"
          readOnly      = false
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.main.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "studio"
        }
      }
      healthCheck = {
        command     = ["CMD-SHELL", "node -e \"fetch('http://localhost:3000/api/platform/profile').then((r) => {if (r.status !== 200) throw new Error(r.status)})\""]
        interval    = 5
        timeout     = 10
        retries     = 3
        startPeriod = 20
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
      image     = "supabase/postgres-meta:v0.99.0"
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
        { name = "PG_META_DB_USER", value = "postgres" },
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
# Upstream moved Logflare + Vector to docker-compose.logs.yml (optional).

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
      image     = "supabase/logflare:1.50.10"
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
        { name = "LOGFLARE_FEATURE_FLAG_OVERRIDE", value = "multibackend=true" },
        { name = "POSTGRES_BACKEND_URL", value = "postgresql://supabase_admin:${var.postgres_password}@db.supabase.internal:${var.postgres_port}/_supabase" },
        { name = "POSTGRES_BACKEND_SCHEMA", value = "_analytics" }
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
        command     = ["CMD-SHELL", "curl -sSfL -o /dev/null http://localhost:4000/health"]
        interval    = 5
        timeout     = 5
        retries     = 10
        startPeriod = 30
      }
    }
  ])
}

# --- Functions ---

locals {
  functions_seed = {
    FUNCTIONS_MAIN_GZ  = base64gzip(file("${path.module}/docker/volumes/functions/main/index.ts"))
    FUNCTIONS_HELLO_GZ = base64gzip(file("${path.module}/docker/volumes/functions/hello/index.ts"))
    FUNCTIONS_DENO_GZ  = base64gzip(file("${path.module}/docker/volumes/functions/deno.jsonc"))
  }
}

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
      image     = "supabase/edge-runtime:v1.76.2"
      essential = true
      portMappings = [
        {
          containerPort = 9000
          protocol      = "tcp"
        }
      ]
      environment = concat([
        # Legacy symmetric HS256 key
        { name = "JWT_SECRET", value = var.jwt_secret },
        { name = "SUPABASE_URL", value = local.internal_api_url },
        { name = "SUPABASE_PUBLIC_URL", value = var.supabase_public_url },
        # Legacy API keys (HS256-signed JWTs)
        { name = "SUPABASE_ANON_KEY", value = var.anon_key },
        { name = "SUPABASE_SERVICE_ROLE_KEY", value = var.service_role_key },
        # New opaque API keys, as JSON maps ({"default":"sb_..."})
        { name = "SUPABASE_PUBLISHABLE_KEYS", value = jsonencode({ default = var.supabase_publishable_key }) },
        { name = "SUPABASE_SECRET_KEYS", value = jsonencode({ default = var.supabase_secret_key }) },
        { name = "SUPABASE_DB_URL", value = "postgresql://postgres:${var.postgres_password}@db.supabase.internal:${var.postgres_port}/${var.postgres_db}" },
        { name = "VERIFY_JWT", value = tostring(var.functions_verify_jwt) }
        ],
        [for k, v in local.functions_seed : { name = k, value = v }],
        local.jwks_env ? [{ name = "SUPABASE_JWKS", value = var.jwt_jwks }] : []
      )
      mountPoints = [
        {
          sourceVolume  = "functions-data"
          containerPath = "/home/deno/functions"
          readOnly      = false
        }
      ]
      # Seed the functions volume, then start the runtime. The main router is
      # template-owned and refreshed on every start; hello/ and deno.jsonc (the
      # import map main uses for every function) are only seeded once.
      entryPoint = ["/bin/sh", "-c"]
      command = [
        <<-EOT
        set -e
        mkdir -p /home/deno/functions/main /home/deno/functions/hello
        echo "$FUNCTIONS_MAIN_GZ" | base64 -d | gunzip > /home/deno/functions/main/index.ts
        [ -e /home/deno/functions/hello/index.ts ] || echo "$FUNCTIONS_HELLO_GZ" | base64 -d | gunzip > /home/deno/functions/hello/index.ts
        [ -e /home/deno/functions/deno.jsonc ] || echo "$FUNCTIONS_DENO_GZ" | base64 -d | gunzip > /home/deno/functions/deno.jsonc
        exec edge-runtime start --user-worker-request-idle-timeout 150000 --main-service /home/deno/functions/main
        EOT
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.main.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "functions"
        }
      }
      healthCheck = {
        command  = ["CMD-SHELL", "timeout 1 bash -c '</dev/tcp/127.0.0.1/9000'"]
        interval = 5
        timeout  = 5
        retries  = 3
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
      image     = "supabase/supavisor:2.9.12"
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
        # pooler.exs registers the tenant against this host
        { name = "POSTGRES_HOST", value = "db.supabase.internal" },
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
      # $(...) — not compose's $$(...) escape, which would reach the shell as the PID
      command = [
        "/bin/sh", "-c",
        "mkdir -p /etc/pooler && echo \"$POOLER_CONFIG\" > /etc/pooler/pooler.exs && /app/bin/migrate && /app/bin/supavisor eval \"$(cat /etc/pooler/pooler.exs)\" && /app/bin/server"
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
        command     = ["CMD", "curl", "-sSfL", "--head", "-o", "/dev/null", "http://127.0.0.1:4000/api/health"]
        interval    = 10
        timeout     = 5
        retries     = 5
        startPeriod = 30
      }
    }
  ])
}
