# --- Auth (GoTrue) ---

resource "kubernetes_deployment" "auth" {
  metadata {
    name      = "auth"
    namespace = kubernetes_namespace.tenant.metadata[0].name
    labels    = { app = "auth", "tenant-id" = var.tenant_id }
  }

  spec {
    replicas = 1
    selector {
      match_labels = { app = "auth" }
    }

    template {
      metadata {
        labels = { app = "auth", "tenant-id" = var.tenant_id }
      }

      spec {
        container {
          name  = "auth"
          image = "supabase/gotrue:v2.196.0"

          port {
            container_port = 9999
            protocol       = "TCP"
          }

          env {
            name  = "GOTRUE_API_HOST"
            value = "0.0.0.0"
          }
          env {
            name  = "GOTRUE_API_PORT"
            value = "9999"
          }
          env {
            name  = "API_EXTERNAL_URL"
            value = local.api_external_url
          }
          env {
            name  = "GOTRUE_DB_DRIVER"
            value = "postgres"
          }
          env {
            name  = "GOTRUE_DB_DATABASE_URL"
            value = local.db_uri_auth
          }
          env {
            name  = "GOTRUE_SITE_URL"
            value = var.site_url
          }
          env {
            name  = "GOTRUE_URI_ALLOW_LIST"
            value = var.additional_redirect_urls
          }
          env {
            name  = "GOTRUE_DISABLE_SIGNUP"
            value = tostring(var.disable_signup)
          }
          env {
            name  = "GOTRUE_JWT_ADMIN_ROLES"
            value = "service_role"
          }
          env {
            name  = "GOTRUE_JWT_AUD"
            value = "authenticated"
          }
          env {
            name  = "GOTRUE_JWT_DEFAULT_GROUP_NAME"
            value = "authenticated"
          }
          env {
            name  = "GOTRUE_JWT_EXP"
            value = tostring(var.jwt_expiry)
          }
          # Legacy symmetric HS256 key
          env {
            name = "GOTRUE_JWT_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.tenant_config.metadata[0].name
                key  = "JWT_SECRET"
              }
            }
          }
          # JSON array of signing JWKs (EC private + legacy symmetric)
          dynamic "env" {
            for_each = local.jwt_keys_enabled ? [1] : []
            content {
              name = "GOTRUE_JWT_KEYS"
              value_from {
                secret_key_ref {
                  name = kubernetes_secret.tenant_config.metadata[0].name
                  key  = "JWT_KEYS"
                }
              }
            }
          }
          env {
            name  = "GOTRUE_JWT_ISSUER"
            value = local.api_external_url
          }
          env {
            name  = "GOTRUE_EXTERNAL_EMAIL_ENABLED"
            value = tostring(var.enable_email_signup)
          }
          env {
            name  = "GOTRUE_EXTERNAL_ANONYMOUS_USERS_ENABLED"
            value = tostring(var.enable_anonymous_users)
          }
          env {
            name  = "GOTRUE_MAILER_AUTOCONFIRM"
            value = tostring(var.enable_email_autoconfirm)
          }
          env {
            name  = "GOTRUE_SMTP_ADMIN_EMAIL"
            value = var.smtp_admin_email
          }
          env {
            name  = "GOTRUE_SMTP_HOST"
            value = var.smtp_host
          }
          env {
            name  = "GOTRUE_SMTP_PORT"
            value = tostring(var.smtp_port)
          }
          env {
            name  = "GOTRUE_SMTP_USER"
            value = var.smtp_user
          }
          env {
            name = "GOTRUE_SMTP_PASS"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.tenant_config.metadata[0].name
                key  = "SMTP_PASS"
              }
            }
          }
          env {
            name  = "GOTRUE_SMTP_SENDER_NAME"
            value = var.smtp_sender_name
          }
          env {
            name  = "GOTRUE_MAILER_URLPATHS_INVITE"
            value = var.mailer_urlpaths_invite
          }
          env {
            name  = "GOTRUE_MAILER_URLPATHS_CONFIRMATION"
            value = var.mailer_urlpaths_confirmation
          }
          env {
            name  = "GOTRUE_MAILER_URLPATHS_RECOVERY"
            value = var.mailer_urlpaths_recovery
          }
          env {
            name  = "GOTRUE_MAILER_URLPATHS_EMAIL_CHANGE"
            value = var.mailer_urlpaths_email_change
          }
          env {
            name  = "GOTRUE_EXTERNAL_PHONE_ENABLED"
            value = tostring(var.enable_phone_signup)
          }
          env {
            name  = "GOTRUE_SMS_AUTOCONFIRM"
            value = tostring(var.enable_phone_autoconfirm)
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = 9999
            }
            period_seconds    = 5
            timeout_seconds   = 5
            failure_threshold = 3
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 9999
            }
            initial_delay_seconds = 10
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }

          resources {
            requests = {
              cpu    = "30m"
              memory = "64Mi"
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

  depends_on = [kubernetes_deployment.db]
}

resource "kubernetes_service" "auth" {
  metadata {
    name      = "auth"
    namespace = kubernetes_namespace.tenant.metadata[0].name
  }
  spec {
    selector = { app = "auth" }
    port {
      port        = 9999
      target_port = 9999
    }
    type = "ClusterIP"
  }
}

# --- PostgREST ---

resource "kubernetes_deployment" "rest" {
  metadata {
    name      = "rest"
    namespace = kubernetes_namespace.tenant.metadata[0].name
    labels    = { app = "rest", "tenant-id" = var.tenant_id }
  }

  spec {
    replicas = 1
    selector {
      match_labels = { app = "rest" }
    }

    template {
      metadata {
        labels = { app = "rest", "tenant-id" = var.tenant_id }
      }

      spec {
        container {
          name    = "rest"
          image   = "postgrest/postgrest:v14.17"
          command = ["postgrest"]

          port {
            container_port = 3000
            protocol       = "TCP"
          }

          env {
            name  = "PGRST_DB_URI"
            value = local.db_uri_rest
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
            name  = "PGRST_DB_ANON_ROLE"
            value = "anon"
          }
          env {
            name  = "PGRST_ADMIN_SERVER_PORT"
            value = "3001"
          }
          env {
            name  = "PGRST_ADMIN_SERVER_HOST"
            value = "localhost"
          }
          # Symmetric secret, or the JWKS when asymmetric keys are configured
          env {
            name = "PGRST_JWT_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.tenant_config.metadata[0].name
                key  = "PGRST_JWT_SECRET"
              }
            }
          }
          env {
            name  = "PGRST_DB_USE_LEGACY_GUCS"
            value = "false"
          }
          env {
            name  = "PGRST_APP_SETTINGS_JWT_EXP"
            value = tostring(var.jwt_expiry)
          }

          # `postgrest --ready` queries the admin server on localhost:3001
          readiness_probe {
            exec {
              command = ["postgrest", "--ready"]
            }
            period_seconds    = 5
            timeout_seconds   = 5
            failure_threshold = 3
          }

          # Not --ready: that fails while the database is down, and restarting
          # PostgREST doesn't help it reconnect.
          liveness_probe {
            tcp_socket {
              port = 3000
            }
            initial_delay_seconds = 10
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }

          resources {
            requests = {
              cpu    = "30m"
              memory = "64Mi"
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

  depends_on = [kubernetes_deployment.db]
}

resource "kubernetes_service" "rest" {
  metadata {
    name      = "rest"
    namespace = kubernetes_namespace.tenant.metadata[0].name
  }
  spec {
    selector = { app = "rest" }
    port {
      port        = 3000
      target_port = 3000
    }
    type = "ClusterIP"
  }
}

# --- Storage API ---
# S3 backend (DO Spaces). Each tenant's files live under
# s3://{bucket}/tenants/{tenant-id}/.

resource "kubernetes_deployment" "storage" {
  metadata {
    name      = "storage"
    namespace = kubernetes_namespace.tenant.metadata[0].name
    labels    = { app = "storage", "tenant-id" = var.tenant_id }
  }

  spec {
    replicas = 1
    selector {
      match_labels = { app = "storage" }
    }

    template {
      metadata {
        labels = { app = "storage", "tenant-id" = var.tenant_id }
      }

      spec {
        container {
          name  = "storage"
          image = "supabase/storage-api:v1.74.0"

          port {
            container_port = 5000
            protocol       = "TCP"
          }

          env {
            name = "ANON_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.tenant_config.metadata[0].name
                key  = "ANON_KEY"
              }
            }
          }
          env {
            name = "SERVICE_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.tenant_config.metadata[0].name
                key  = "SERVICE_ROLE_KEY"
              }
            }
          }
          env {
            name  = "POSTGREST_URL"
            value = "http://rest:3000"
          }
          # Legacy symmetric HS256 key
          env {
            name = "AUTH_JWT_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.tenant_config.metadata[0].name
                key  = "JWT_SECRET"
              }
            }
          }
          # JWKS for token verification (EC public + legacy symmetric)
          dynamic "env" {
            for_each = local.jwt_jwks_enabled ? [1] : []
            content {
              name = "JWT_JWKS"
              value_from {
                secret_key_ref {
                  name = kubernetes_secret.tenant_config.metadata[0].name
                  key  = "JWT_JWKS"
                }
              }
            }
          }
          env {
            name  = "DATABASE_URL"
            value = local.db_uri_stor
          }
          env {
            name  = "STORAGE_PUBLIC_URL"
            value = local.api_url
          }
          env {
            name  = "REQUEST_ALLOW_X_FORWARDED_PATH"
            value = "true"
          }
          env {
            name  = "FILE_SIZE_LIMIT"
            value = "52428800"
          }
          # S3 backend pointing to DO Spaces
          env {
            name  = "STORAGE_BACKEND"
            value = "s3"
          }
          env {
            name  = "GLOBAL_S3_BUCKET"
            value = var.spaces_bucket
          }
          env {
            name  = "GLOBAL_S3_ENDPOINT"
            value = var.spaces_endpoint
          }
          env {
            name  = "GLOBAL_S3_FORCE_PATH_STYLE"
            value = "true"
          }
          env {
            name  = "GLOBAL_S3_PREFIX"
            value = "tenants/${var.tenant_id}"
          }
          env {
            name = "AWS_ACCESS_KEY_ID"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.tenant_config.metadata[0].name
                key  = "SPACES_ACCESS_KEY"
              }
            }
          }
          env {
            name = "AWS_SECRET_ACCESS_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.tenant_config.metadata[0].name
                key  = "SPACES_SECRET_KEY"
              }
            }
          }
          env {
            name  = "REGION"
            value = var.spaces_region
          }
          env {
            name  = "TENANT_ID"
            value = var.tenant_id
          }
          env {
            name  = "ENABLE_IMAGE_TRANSFORMATION"
            value = "true"
          }
          # ImgProxy runs in the shared namespace
          env {
            name  = "IMGPROXY_URL"
            value = "http://${local.imgproxy_host}:5001"
          }
          env {
            name = "S3_PROTOCOL_ACCESS_KEY_ID"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.tenant_config.metadata[0].name
                key  = "S3_PROTOCOL_ACCESS_KEY_ID"
              }
            }
          }
          env {
            name = "S3_PROTOCOL_ACCESS_KEY_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.tenant_config.metadata[0].name
                key  = "S3_PROTOCOL_ACCESS_KEY_SECRET"
              }
            }
          }

          readiness_probe {
            http_get {
              path = "/status"
              port = 5000
            }
            period_seconds    = 5
            timeout_seconds   = 5
            failure_threshold = 3
          }

          liveness_probe {
            http_get {
              path = "/status"
              port = 5000
            }
            initial_delay_seconds = 10
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "300m"
              memory = "384Mi"
            }
          }
        }
      }
    }
  }

  depends_on = [kubernetes_deployment.db]
}

resource "kubernetes_service" "storage" {
  metadata {
    name      = "storage"
    namespace = kubernetes_namespace.tenant.metadata[0].name
  }
  spec {
    selector = { app = "storage" }
    port {
      port        = 5000
      target_port = 5000
    }
    type = "ClusterIP"
  }
}

# --- Meta (PG Meta) ---
# Per tenant, connected to the tenant's own database. The gateway only lets
# the service_role/secret key reach it (/pg/).

resource "kubernetes_deployment" "meta" {
  metadata {
    name      = "meta"
    namespace = kubernetes_namespace.tenant.metadata[0].name
    labels    = { app = "meta", "tenant-id" = var.tenant_id }
  }

  spec {
    replicas = 1
    selector {
      match_labels = { app = "meta" }
    }

    template {
      metadata {
        labels = { app = "meta", "tenant-id" = var.tenant_id }
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
            value = local.db_host
          }
          env {
            name  = "PG_META_DB_PORT"
            value = tostring(local.db_port)
          }
          env {
            name  = "PG_META_DB_NAME"
            value = local.db_name
          }
          env {
            name  = "PG_META_DB_USER"
            value = "postgres"
          }
          env {
            name = "PG_META_DB_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.tenant_config.metadata[0].name
                key  = "POSTGRES_PASSWORD"
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
              cpu    = "20m"
              memory = "64Mi"
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

  depends_on = [kubernetes_deployment.db]
}

resource "kubernetes_service" "meta" {
  metadata {
    name      = "meta"
    namespace = kubernetes_namespace.tenant.metadata[0].name
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

# --- Edge Functions ---

resource "kubernetes_deployment" "functions" {
  metadata {
    name      = "functions"
    namespace = kubernetes_namespace.tenant.metadata[0].name
    labels    = { app = "functions", "tenant-id" = var.tenant_id }
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
        labels = { app = "functions", "tenant-id" = var.tenant_id }
        annotations = {
          "checksum/config" = sha256(jsonencode(kubernetes_config_map.functions_init.data))
        }
      }

      spec {
        # The main router is template-owned and refreshed on every start, so
        # upstream fixes reach existing volumes. hello/ and deno.jsonc (the
        # import map main uses for every function) are only seeded once, so
        # tenant changes survive.
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
                name = kubernetes_secret.tenant_config.metadata[0].name
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
                  name = kubernetes_secret.tenant_config.metadata[0].name
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
            value = local.api_url
          }
          # Legacy API keys (HS256-signed JWTs)
          env {
            name = "SUPABASE_ANON_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.tenant_config.metadata[0].name
                key  = "ANON_KEY"
              }
            }
          }
          env {
            name = "SUPABASE_SERVICE_ROLE_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.tenant_config.metadata[0].name
                key  = "SERVICE_ROLE_KEY"
              }
            }
          }
          # New opaque API keys, as JSON maps ({"default":"sb_..."})
          env {
            name = "SUPABASE_PUBLISHABLE_KEYS"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.tenant_config.metadata[0].name
                key  = "SUPABASE_PUBLISHABLE_KEYS"
              }
            }
          }
          env {
            name = "SUPABASE_SECRET_KEYS"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.tenant_config.metadata[0].name
                key  = "SUPABASE_SECRET_KEYS"
              }
            }
          }
          # The tenant's own database, as on the platform
          env {
            name  = "SUPABASE_DB_URL"
            value = local.db_uri_fn
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
              cpu    = "40m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
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
    namespace = kubernetes_namespace.tenant.metadata[0].name
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

# --- API Gateway (Envoy) ---
# Upstream's gateway config, per tenant: API key checks, sb_ key translation,
# CORS and the route restrictions (e.g. no anon access to /rest/v1/ or the
# Realtime tenants API) behave exactly as on a single-tenant deployment. The
# shared tenant router forwards {tenant-id}.{api_domain} here.

resource "kubernetes_deployment" "api_gw" {
  metadata {
    name      = "api-gw"
    namespace = kubernetes_namespace.tenant.metadata[0].name
    labels    = { app = "api-gw", "tenant-id" = var.tenant_id }
  }

  spec {
    replicas = 1
    selector {
      match_labels = { app = "api-gw" }
    }

    template {
      metadata {
        labels = { app = "api-gw", "tenant-id" = var.tenant_id }
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
                name = kubernetes_secret.tenant_config.metadata[0].name
                key  = "ANON_KEY"
              }
            }
          }
          env {
            name = "SERVICE_ROLE_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.tenant_config.metadata[0].name
                key  = "SERVICE_ROLE_KEY"
              }
            }
          }
          env {
            name = "SUPABASE_PUBLISHABLE_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.tenant_config.metadata[0].name
                key  = "SUPABASE_PUBLISHABLE_KEY"
              }
            }
          }
          env {
            name = "SUPABASE_SECRET_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.tenant_config.metadata[0].name
                key  = "SUPABASE_SECRET_KEY"
              }
            }
          }
          env {
            name = "ANON_KEY_ASYMMETRIC"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.tenant_config.metadata[0].name
                key  = "ANON_KEY_ASYMMETRIC"
              }
            }
          }
          env {
            name = "SERVICE_ROLE_KEY_ASYMMETRIC"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.tenant_config.metadata[0].name
                key  = "SERVICE_ROLE_KEY_ASYMMETRIC"
              }
            }
          }
          env {
            name  = "SUPABASE_PUBLIC_URL"
            value = local.api_url
          }
          env {
            name  = "DASHBOARD_USERNAME"
            value = "supabase"
          }
          env {
            name = "DASHBOARD_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.tenant_config.metadata[0].name
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
              cpu    = "20m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "300m"
              memory = "256Mi"
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
    namespace = kubernetes_namespace.tenant.metadata[0].name
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
