# --- API Gateway (Envoy) ---
# Upstream's default gateway since self-hosted 0.8.0 (Kong is deprecated).
# docker-entrypoint.sh renders lds.template.yaml with the API keys and the
# Studio basic-auth credentials, then execs Envoy.

resource "kubernetes_deployment" "api_gw" {
  metadata {
    name      = "api-gw"
    namespace = kubernetes_namespace.supabase.metadata[0].name
    labels    = { app = "api-gw" }
  }

  spec {
    replicas = 1
    selector {
      match_labels = { app = "api-gw" }
    }

    template {
      metadata {
        labels = { app = "api-gw" }
        annotations = {
          "checksum/config" = sha256(jsonencode(kubernetes_config_map.envoy_config.data))
        }
      }

      spec {
        container {
          name  = "api-gw"
          image = "envoyproxy/envoy:v1.39.1"

          port {
            container_port = 8000
            protocol       = "TCP"
          }

          env {
            name = "ANON_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.supabase_config.metadata[0].name
                key  = "ANON_KEY"
              }
            }
          }
          env {
            name = "SERVICE_ROLE_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.supabase_config.metadata[0].name
                key  = "SERVICE_ROLE_KEY"
              }
            }
          }
          env {
            name = "SUPABASE_PUBLISHABLE_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.supabase_config.metadata[0].name
                key  = "SUPABASE_PUBLISHABLE_KEY"
              }
            }
          }
          env {
            name = "SUPABASE_SECRET_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.supabase_config.metadata[0].name
                key  = "SUPABASE_SECRET_KEY"
              }
            }
          }
          env {
            name = "ANON_KEY_ASYMMETRIC"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.supabase_config.metadata[0].name
                key  = "ANON_KEY_ASYMMETRIC"
              }
            }
          }
          env {
            name = "SERVICE_ROLE_KEY_ASYMMETRIC"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.supabase_config.metadata[0].name
                key  = "SERVICE_ROLE_KEY_ASYMMETRIC"
              }
            }
          }
          env {
            name  = "SUPABASE_PUBLIC_URL"
            value = var.supabase_public_url
          }
          env {
            name  = "DASHBOARD_USERNAME"
            value = var.dashboard_username
          }
          env {
            name = "DASHBOARD_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.supabase_config.metadata[0].name
                key  = "DASHBOARD_PASSWORD"
              }
            }
          }

          volume_mount {
            name       = "envoy-config"
            mount_path = "/etc/envoy-config"
            read_only  = true
          }

          # The entrypoint writes lds.yaml next to the other configs, so they
          # are copied out of the read-only ConfigMap mount first.
          command = [
            "/bin/sh", "-c",
            "cp /etc/envoy-config/envoy.yaml /etc/envoy-config/cds.yaml /etc/envoy-config/lds.template.yaml /etc/envoy/ && exec /bin/sh /etc/envoy-config/docker-entrypoint.sh"
          ]

          # TCP check, as upstream: the image has no curl or wget
          readiness_probe {
            tcp_socket {
              port = 8000
            }
            period_seconds    = 5
            timeout_seconds   = 5
            failure_threshold = 3
          }

          liveness_probe {
            tcp_socket {
              port = 8000
            }
            initial_delay_seconds = 10
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }
        }

        volume {
          name = "envoy-config"
          config_map {
            name = kubernetes_config_map.envoy_config.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "api_gw" {
  metadata {
    name      = "api-gw"
    namespace = kubernetes_namespace.supabase.metadata[0].name
  }
  spec {
    selector = { app = "api-gw" }
    port {
      name        = "http"
      port        = 8000
      target_port = 8000
    }
    type = "ClusterIP"
  }
}

# --- Studio ---

resource "kubernetes_deployment" "studio" {
  metadata {
    name      = "studio"
    namespace = kubernetes_namespace.supabase.metadata[0].name
    labels    = { app = "studio" }
  }

  spec {
    replicas = 1
    strategy {
      type = "Recreate" # snippets PVC is ReadWriteOnce
    }
    selector {
      match_labels = { app = "studio" }
    }

    template {
      metadata {
        labels = { app = "studio" }
      }

      spec {
        container {
          name  = "studio"
          image = "supabase/studio:2026.09.07-sha-7996410"

          port {
            container_port = 3000
            protocol       = "TCP"
          }

          # Listen on all IPv4 interfaces
          env {
            name  = "HOSTNAME"
            value = "0.0.0.0"
          }
          env {
            name  = "STUDIO_PG_META_URL"
            value = "http://meta:8080"
          }
          env {
            name  = "POSTGRES_PORT"
            value = tostring(var.postgres_port)
          }
          env {
            name  = "POSTGRES_HOST"
            value = "db"
          }
          env {
            name  = "POSTGRES_DB"
            value = var.postgres_db
          }
          env {
            name = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.supabase_config.metadata[0].name
                key  = "POSTGRES_PASSWORD"
              }
            }
          }
          # See: https://supabase.com/docs/guides/self-hosting/remove-superuser-access
          env {
            name  = "POSTGRES_USER_READ_WRITE"
            value = "postgres"
          }
          env {
            name = "PG_META_CRYPTO_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.supabase_config.metadata[0].name
                key  = "PG_META_CRYPTO_KEY"
              }
            }
          }
          env {
            name  = "PGRST_DB_SCHEMAS"
            value = var.pgrst_db_schemas
          }
          env {
            name  = "PGRST_DB_MAX_ROWS"
            value = tostring(var.pgrst_db_max_rows)
          }
          env {
            name  = "PGRST_DB_EXTRA_SEARCH_PATH"
            value = var.pgrst_db_extra_search_path
          }
          env {
            name  = "DEFAULT_ORGANIZATION_NAME"
            value = var.studio_default_organization
          }
          env {
            name  = "DEFAULT_PROJECT_NAME"
            value = var.studio_default_project
          }
          env {
            name = "OPENAI_API_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.supabase_config.metadata[0].name
                key  = "OPENAI_API_KEY"
              }
            }
          }
          env {
            name  = "SUPABASE_URL"
            value = local.internal_api_url
          }
          env {
            name  = "SUPABASE_PUBLIC_URL"
            value = var.supabase_public_url
          }
          env {
            name = "SUPABASE_ANON_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.supabase_config.metadata[0].name
                key  = "ANON_KEY"
              }
            }
          }
          env {
            name = "SUPABASE_SERVICE_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.supabase_config.metadata[0].name
                key  = "SERVICE_ROLE_KEY"
              }
            }
          }
          env {
            name = "AUTH_JWT_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.supabase_config.metadata[0].name
                key  = "JWT_SECRET"
              }
            }
          }
          env {
            name = "SUPABASE_PUBLISHABLE_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.supabase_config.metadata[0].name
                key  = "SUPABASE_PUBLISHABLE_KEY"
              }
            }
          }
          env {
            name = "SUPABASE_SECRET_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.supabase_config.metadata[0].name
                key  = "SUPABASE_SECRET_KEY"
              }
            }
          }
          # Logs Explorer, as in upstream docker-compose.logs.yml
          env {
            name = "LOGFLARE_PRIVATE_ACCESS_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.supabase_config.metadata[0].name
                key  = "LOGFLARE_PRIVATE_ACCESS_TOKEN"
              }
            }
          }
          env {
            name  = "LOGFLARE_URL"
            value = "http://analytics:4000"
          }
          env {
            name  = "ENABLED_FEATURES_LOGS_ALL"
            value = "true"
          }
          env {
            name  = "SNIPPETS_MANAGEMENT_FOLDER"
            value = "/app/snippets"
          }

          volume_mount {
            name       = "snippets"
            mount_path = "/app/snippets"
          }

          readiness_probe {
            http_get {
              path = "/api/platform/profile"
              port = 3000
            }
            initial_delay_seconds = 10
            period_seconds        = 5
            timeout_seconds       = 10
            failure_threshold     = 3
          }

          liveness_probe {
            http_get {
              path = "/api/platform/profile"
              port = 3000
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            timeout_seconds       = 10
            failure_threshold     = 3
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "1Gi"
            }
          }
        }

        volume {
          name = "snippets"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.studio_snippets.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "studio" {
  metadata {
    name      = "studio"
    namespace = kubernetes_namespace.supabase.metadata[0].name
  }
  spec {
    selector = { app = "studio" }
    port {
      port        = 3000
      target_port = 3000
    }
    type = "ClusterIP"
  }
}

# --- Meta (PG Meta) ---

resource "kubernetes_deployment" "meta" {
  metadata {
    name      = "meta"
    namespace = kubernetes_namespace.supabase.metadata[0].name
    labels    = { app = "meta" }
  }

  spec {
    replicas = 1
    selector {
      match_labels = { app = "meta" }
    }

    template {
      metadata {
        labels = { app = "meta" }
      }

      spec {
        container {
          name  = "meta"
          image = "supabase/postgres-meta:v0.99.0"

          port {
            container_port = 8080
            protocol       = "TCP"
          }

          env {
            name  = "PG_META_PORT"
            value = "8080"
          }
          env {
            name  = "PG_META_DB_HOST"
            value = "db"
          }
          env {
            name  = "PG_META_DB_PORT"
            value = tostring(var.postgres_port)
          }
          env {
            name  = "PG_META_DB_NAME"
            value = var.postgres_db
          }
          env {
            name  = "PG_META_DB_USER"
            value = "postgres"
          }
          env {
            name = "PG_META_DB_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.supabase_config.metadata[0].name
                key  = "POSTGRES_PASSWORD"
              }
            }
          }
          env {
            name = "CRYPTO_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.supabase_config.metadata[0].name
                key  = "PG_META_CRYPTO_KEY"
              }
            }
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            period_seconds    = 5
            timeout_seconds   = 5
            failure_threshold = 3
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "meta" {
  metadata {
    name      = "meta"
    namespace = kubernetes_namespace.supabase.metadata[0].name
  }
  spec {
    selector = { app = "meta" }
    port {
      port        = 8080
      target_port = 8080
    }
    type = "ClusterIP"
  }
}

# --- Analytics (Logflare) ---
# Upstream moved Logflare + Vector to docker-compose.logs.yml (optional). We
# always run them so Studio's Logs Explorer works.

resource "kubernetes_deployment" "analytics" {
  metadata {
    name      = "analytics"
    namespace = kubernetes_namespace.supabase.metadata[0].name
    labels    = { app = "analytics" }
  }

  spec {
    replicas = 1
    selector {
      match_labels = { app = "analytics" }
    }

    template {
      metadata {
        labels = { app = "analytics" }
      }

      spec {
        container {
          name  = "analytics"
          image = "supabase/logflare:1.50.10"

          port {
            container_port = 4000
            protocol       = "TCP"
          }

          env {
            name  = "LOGFLARE_NODE_HOST"
            value = "127.0.0.1"
          }
          env {
            name  = "DB_USERNAME"
            value = "supabase_admin"
          }
          env {
            name  = "DB_DATABASE"
            value = "_supabase"
          }
          env {
            name  = "DB_HOSTNAME"
            value = "db"
          }
          env {
            name  = "DB_PORT"
            value = tostring(var.postgres_port)
          }
          env {
            name = "DB_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.supabase_config.metadata[0].name
                key  = "POSTGRES_PASSWORD"
              }
            }
          }
          env {
            name  = "DB_SCHEMA"
            value = "_analytics"
          }
          # Enable single-tenant mode for Logflare
          env {
            name  = "LOGFLARE_SINGLE_TENANT"
            value = "true"
          }
          # Seed Supabase-related metadata
          env {
            name  = "LOGFLARE_SUPABASE_MODE"
            value = "true"
          }
          env {
            name = "LOGFLARE_PUBLIC_ACCESS_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.supabase_config.metadata[0].name
                key  = "LOGFLARE_PUBLIC_ACCESS_TOKEN"
              }
            }
          }
          env {
            name = "LOGFLARE_PRIVATE_ACCESS_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.supabase_config.metadata[0].name
                key  = "LOGFLARE_PRIVATE_ACCESS_TOKEN"
              }
            }
          }
          env {
            name  = "LOGFLARE_FEATURE_FLAG_OVERRIDE"
            value = "multibackend=true"
          }
          env {
            name  = "POSTGRES_BACKEND_URL"
            value = "postgresql://supabase_admin:${var.postgres_password}@db:${var.postgres_port}/_supabase"
          }
          env {
            name  = "POSTGRES_BACKEND_SCHEMA"
            value = "_analytics"
          }

          startup_probe {
            http_get {
              path = "/health"
              port = 4000
            }
            period_seconds    = 5
            timeout_seconds   = 5
            failure_threshold = 36
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 4000
            }
            period_seconds    = 10
            timeout_seconds   = 5
            failure_threshold = 10
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "300m"
              memory = "512Mi"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "analytics" {
  metadata {
    name      = "analytics"
    namespace = kubernetes_namespace.supabase.metadata[0].name
  }
  spec {
    selector = { app = "analytics" }
    port {
      port        = 4000
      target_port = 4000
    }
    type = "ClusterIP"
  }
}

# --- Edge Functions ---

resource "kubernetes_deployment" "functions" {
  metadata {
    name      = "functions"
    namespace = kubernetes_namespace.supabase.metadata[0].name
    labels    = { app = "functions" }
  }

  spec {
    replicas = 1
    strategy {
      type = "Recreate" # PVC is ReadWriteOnce
    }
    selector {
      match_labels = { app = "functions" }
    }

    template {
      metadata {
        labels = { app = "functions" }
        annotations = {
          "checksum/config" = sha256(jsonencode(kubernetes_config_map.functions_init.data))
        }
      }

      spec {
        # The main router is template-owned and refreshed on every start, so
        # upstream fixes reach existing volumes. hello/ and deno.jsonc (the
        # import map main uses for every function) are only seeded once, so
        # user changes survive.
        init_container {
          name  = "init-functions"
          image = "busybox:1.36"
          command = [
            "sh", "-c",
            "mkdir -p /functions/main /functions/hello && cp /init/main-index.ts /functions/main/index.ts && cp -n /init/hello-index.ts /functions/hello/index.ts && cp -n /init/deno.jsonc /functions/deno.jsonc"
          ]

          volume_mount {
            name       = "functions-data"
            mount_path = "/functions"
          }
          volume_mount {
            name       = "functions-init"
            mount_path = "/init"
            read_only  = true
          }
        }

        container {
          name  = "functions"
          image = "supabase/edge-runtime:v1.76.2"
          command = [
            "start",
            "--user-worker-request-idle-timeout", "150000",
            "--main-service", "/home/deno/functions/main"
          ]

          port {
            container_port = 9000
            protocol       = "TCP"
          }

          # Legacy symmetric HS256 key
          env {
            name = "JWT_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.supabase_config.metadata[0].name
                key  = "JWT_SECRET"
              }
            }
          }
          # JWKS for token verification (EC public + legacy symmetric)
          dynamic "env" {
            for_each = local.jwt_jwks_enabled ? [1] : []
            content {
              name = "SUPABASE_JWKS"
              value_from {
                secret_key_ref {
                  name = kubernetes_secret.supabase_config.metadata[0].name
                  key  = "JWT_JWKS"
                }
              }
            }
          }
          env {
            name  = "SUPABASE_URL"
            value = local.internal_api_url
          }
          env {
            name  = "SUPABASE_PUBLIC_URL"
            value = var.supabase_public_url
          }
          # Legacy API keys (HS256-signed JWTs)
          env {
            name = "SUPABASE_ANON_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.supabase_config.metadata[0].name
                key  = "ANON_KEY"
              }
            }
          }
          env {
            name = "SUPABASE_SERVICE_ROLE_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.supabase_config.metadata[0].name
                key  = "SERVICE_ROLE_KEY"
              }
            }
          }
          # New opaque API keys, as JSON maps ({"default":"sb_..."})
          env {
            name = "SUPABASE_PUBLISHABLE_KEYS"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.supabase_config.metadata[0].name
                key  = "SUPABASE_PUBLISHABLE_KEYS"
              }
            }
          }
          env {
            name = "SUPABASE_SECRET_KEYS"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.supabase_config.metadata[0].name
                key  = "SUPABASE_SECRET_KEYS"
              }
            }
          }
          env {
            name  = "SUPABASE_DB_URL"
            value = "postgresql://postgres:${var.postgres_password}@db:${var.postgres_port}/${var.postgres_db}"
          }
          env {
            name  = "VERIFY_JWT"
            value = tostring(var.functions_verify_jwt)
          }

          volume_mount {
            name       = "functions-data"
            mount_path = "/home/deno/functions"
          }
          volume_mount {
            name       = "deno-cache"
            mount_path = "/root/.cache/deno"
          }

          readiness_probe {
            tcp_socket {
              port = 9000
            }
            period_seconds    = 5
            timeout_seconds   = 5
            failure_threshold = 3
          }

          liveness_probe {
            tcp_socket {
              port = 9000
            }
            initial_delay_seconds = 10
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "1Gi"
            }
          }
        }

        volume {
          name = "functions-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.functions_data.metadata[0].name
          }
        }

        volume {
          name = "functions-init"
          config_map {
            name = kubernetes_config_map.functions_init.metadata[0].name
          }
        }

        volume {
          name = "deno-cache"
          empty_dir {}
        }
      }
    }
  }
}

resource "kubernetes_service" "functions" {
  metadata {
    name      = "functions"
    namespace = kubernetes_namespace.supabase.metadata[0].name
  }
  spec {
    selector = { app = "functions" }
    port {
      port        = 9000
      target_port = 9000
    }
    type = "ClusterIP"
  }
}

# --- Supavisor (Connection Pooler) ---

resource "kubernetes_deployment" "supavisor" {
  metadata {
    name      = "supavisor"
    namespace = kubernetes_namespace.supabase.metadata[0].name
    labels    = { app = "supavisor" }
  }

  spec {
    replicas = 1
    selector {
      match_labels = { app = "supavisor" }
    }

    template {
      metadata {
        labels = { app = "supavisor" }
        annotations = {
          "checksum/config" = sha256(kubernetes_config_map.pooler_config.data["pooler.exs"])
        }
      }

      spec {
        container {
          name  = "supavisor"
          image = "supabase/supavisor:2.9.12"

          port {
            container_port = 5432
            protocol       = "TCP"
          }
          port {
            container_port = 6543
            protocol       = "TCP"
          }
          port {
            container_port = 4000
            protocol       = "TCP"
          }

          env {
            name  = "PORT"
            value = "4000"
          }
          env {
            name  = "POSTGRES_PORT"
            value = tostring(var.postgres_port)
          }
          # pooler.exs registers the tenant against this host
          env {
            name  = "POSTGRES_HOST"
            value = "db"
          }
          env {
            name  = "POSTGRES_DB"
            value = var.postgres_db
          }
          env {
            name = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.supabase_config.metadata[0].name
                key  = "POSTGRES_PASSWORD"
              }
            }
          }
          env {
            name  = "DATABASE_URL"
            value = "ecto://supabase_admin:${var.postgres_password}@db:${var.postgres_port}/_supabase"
          }
          env {
            name  = "CLUSTER_POSTGRES"
            value = "true"
          }
          env {
            name = "SECRET_KEY_BASE"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.supabase_config.metadata[0].name
                key  = "SECRET_KEY_BASE"
              }
            }
          }
          env {
            name = "VAULT_ENC_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.supabase_config.metadata[0].name
                key  = "VAULT_ENC_KEY"
              }
            }
          }
          env {
            name = "API_JWT_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.supabase_config.metadata[0].name
                key  = "JWT_SECRET"
              }
            }
          }
          env {
            name = "METRICS_JWT_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.supabase_config.metadata[0].name
                key  = "JWT_SECRET"
              }
            }
          }
          env {
            name  = "REGION"
            value = "local"
          }
          env {
            name  = "ERL_AFLAGS"
            value = "-proto_dist inet_tcp"
          }
          env {
            name  = "POOLER_TENANT_ID"
            value = var.pooler_tenant_id
          }
          env {
            name  = "POOLER_DEFAULT_POOL_SIZE"
            value = tostring(var.pooler_default_pool_size)
          }
          env {
            name  = "POOLER_MAX_CLIENT_CONN"
            value = tostring(var.pooler_max_client_conn)
          }
          env {
            name  = "POOLER_POOL_MODE"
            value = "transaction"
          }
          env {
            name  = "DB_POOL_SIZE"
            value = tostring(var.pooler_db_pool_size)
          }

          # Mount pooler config from ConfigMap
          volume_mount {
            name       = "pooler-config"
            mount_path = "/etc/pooler"
            read_only  = true
          }

          command = [
            "/bin/sh", "-c",
            "/app/bin/migrate && /app/bin/supavisor eval \"$(cat /etc/pooler/pooler.exs)\" && /app/bin/server"
          ]

          startup_probe {
            http_get {
              path = "/api/health"
              port = 4000
            }
            period_seconds    = 5
            timeout_seconds   = 5
            failure_threshold = 36
          }

          liveness_probe {
            http_get {
              path = "/api/health"
              port = 4000
            }
            period_seconds    = 10
            timeout_seconds   = 5
            failure_threshold = 5
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "300m"
              memory = "512Mi"
            }
          }
        }

        volume {
          name = "pooler-config"
          config_map {
            name = kubernetes_config_map.pooler_config.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "supavisor" {
  metadata {
    name      = "supavisor"
    namespace = kubernetes_namespace.supabase.metadata[0].name
  }
  spec {
    selector = { app = "supavisor" }
    port {
      name        = "postgres"
      port        = 5432
      target_port = 5432
    }
    port {
      name        = "pooler"
      port        = 6543
      target_port = 6543
    }
    type = "ClusterIP"
  }
}
