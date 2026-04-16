# --- Kong (API Gateway) ---

resource "kubernetes_deployment" "kong" {
  metadata {
    name      = "kong"
    namespace = kubernetes_namespace.supabase.metadata[0].name
    labels    = { app = "kong" }
  }

  spec {
    replicas = 1
    selector {
      match_labels = { app = "kong" }
    }

    template {
      metadata {
        labels = { app = "kong" }
      }

      spec {
        container {
          name  = "kong"
          image = "kong/kong:3.9.1"

          port {
            container_port = 8000
            protocol       = "TCP"
          }
          port {
            container_port = 8443
            protocol       = "TCP"
          }

          env {
            name  = "KONG_DATABASE"
            value = "off"
          }
          env {
            name  = "KONG_DECLARATIVE_CONFIG"
            value = "/usr/local/kong/kong.yml"
          }
          env {
            name  = "KONG_DNS_ORDER"
            value = "LAST,A,CNAME"
          }
          env {
            name  = "KONG_DNS_NOT_FOUND_TTL"
            value = "1"
          }
          env {
            name  = "KONG_PLUGINS"
            value = "request-transformer,cors,key-auth,acl,basic-auth,request-termination,ip-restriction,post-function"
          }
          env {
            name  = "KONG_NGINX_PROXY_PROXY_BUFFER_SIZE"
            value = "160k"
          }
          env {
            name  = "KONG_NGINX_PROXY_PROXY_BUFFERS"
            value = "64 160k"
          }
          env {
            name  = "KONG_PROXY_ACCESS_LOG"
            value = "/dev/stdout combined"
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

          # Mount kong config and entrypoint from ConfigMap
          volume_mount {
            name       = "kong-config"
            mount_path = "/home/kong/config"
            read_only  = true
          }

          # Use entrypoint script from ConfigMap to process env var substitution
          command = [
            "bash", "-c",
            "cp /home/kong/config/kong.yml /home/kong/temp.yml && cp /home/kong/config/kong-entrypoint.sh /home/kong/kong-entrypoint.sh && chmod +x /home/kong/kong-entrypoint.sh && /home/kong/kong-entrypoint.sh"
          ]

          liveness_probe {
            exec {
              command = ["kong", "health"]
            }
            initial_delay_seconds = 15
            period_seconds        = 10
            timeout_seconds       = 10
            failure_threshold     = 3
          }

          resources {
            requests = {
              cpu    = "200m"
              memory = "512Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "1Gi"
            }
          }
        }

        volume {
          name = "kong-config"
          config_map {
            name = kubernetes_config_map.kong_config.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "kong" {
  metadata {
    name      = "kong"
    namespace = kubernetes_namespace.supabase.metadata[0].name
  }
  spec {
    selector = { app = "kong" }
    port {
      name        = "http"
      port        = 8000
      target_port = 8000
    }
    port {
      name        = "https"
      port        = 8443
      target_port = 8443
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
          image = "supabase/studio:2026.04.08-sha-205cbe7"

          port {
            container_port = 3000
            protocol       = "TCP"
          }

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
            value = "http://kong:8000"
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
            name = "LOGFLARE_API_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.supabase_config.metadata[0].name
                key  = "LOGFLARE_PUBLIC_ACCESS_TOKEN"
              }
            }
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
            name  = "LOGFLARE_URL"
            value = "http://analytics:4000"
          }
          env {
            name  = "NEXT_PUBLIC_ENABLE_LOGS"
            value = "true"
          }
          env {
            name  = "NEXT_ANALYTICS_BACKEND_PROVIDER"
            value = "postgres"
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
          image = "supabase/postgres-meta:v0.96.3"

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
            value = "supabase_admin"
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
          image = "supabase/logflare:1.36.1"

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
            name  = "LOGFLARE_SINGLE_TENANT"
            value = "true"
          }
          env {
            name  = "LOGFLARE_SUPABASE_MODE"
            value = "true"
          }
          env {
            name  = "POSTGRES_BACKEND_URL"
            value = "postgresql://supabase_admin:${var.postgres_password}@db:${var.postgres_port}/_supabase"
          }
          env {
            name  = "POSTGRES_BACKEND_SCHEMA"
            value = "_analytics"
          }
          env {
            name  = "LOGFLARE_FEATURE_FLAG_OVERRIDE"
            value = "multibackend=true"
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 4000
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 10
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
      }

      spec {
        # Init container seeds the PVC with default edge functions on first deploy.
        # Uses cp -n (no-clobber) so user-deployed functions are never overwritten.
        init_container {
          name  = "init-functions"
          image = "busybox:1.36"
          command = [
            "sh", "-c",
            "mkdir -p /functions/main /functions/hello && cp -n /init/main-index.ts /functions/main/index.ts 2>/dev/null; cp -n /init/hello-index.ts /functions/hello/index.ts 2>/dev/null; true"
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
          name    = "functions"
          image   = "supabase/edge-runtime:v1.71.2"
          command = ["start", "--main-service", "/home/deno/functions/main"]

          port {
            container_port = 9000
            protocol       = "TCP"
          }

          env {
            name = "JWT_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.supabase_config.metadata[0].name
                key  = "JWT_SECRET"
              }
            }
          }
          env {
            name  = "SUPABASE_URL"
            value = "http://kong:8000"
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
            name = "SUPABASE_SERVICE_ROLE_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.supabase_config.metadata[0].name
                key  = "SERVICE_ROLE_KEY"
              }
            }
          }
          env {
            name = "SUPABASE_PUBLISHABLE_KEYS"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.supabase_config.metadata[0].name
                key  = "SUPABASE_PUBLISHABLE_KEY"
              }
            }
          }
          env {
            name = "SUPABASE_SECRET_KEYS"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.supabase_config.metadata[0].name
                key  = "SUPABASE_SECRET_KEY"
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
      }

      spec {
        container {
          name  = "supavisor"
          image = "supabase/supavisor:2.7.4"

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

          liveness_probe {
            http_get {
              path = "/api/health"
              port = 4000
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 5
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
