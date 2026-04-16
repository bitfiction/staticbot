# --- Auth (GoTrue) ---
# Per-tenant instance with static DB connection to tenant_{id} database.

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
          image = "supabase/gotrue:v2.186.0"

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
            value = local.api_url
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
          env {
            name = "GOTRUE_JWT_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.tenant_config.metadata[0].name
                key  = "JWT_SECRET"
              }
            }
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
              memory = "100Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "256Mi"
            }
          }
        }
      }
    }
  }
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
# Per-tenant instance with static DB connection to tenant_{id} database.

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
          image   = "postgrest/postgrest:v14.8"
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
            name = "PGRST_JWT_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.tenant_config.metadata[0].name
                key  = "JWT_SECRET"
              }
            }
          }
          env {
            name  = "PGRST_DB_USE_LEGACY_GUCS"
            value = "false"
          }
          env {
            name = "PGRST_APP_SETTINGS_JWT_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.tenant_config.metadata[0].name
                key  = "JWT_SECRET"
              }
            }
          }
          env {
            name  = "PGRST_APP_SETTINGS_JWT_EXP"
            value = tostring(var.jwt_expiry)
          }

          resources {
            requests = {
              cpu    = "30m"
              memory = "100Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "256Mi"
            }
          }
        }
      }
    }
  }
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
# Per-tenant instance using S3 backend (DO Spaces).
# Each tenant's files are stored under s3://{bucket}/tenants/{tenant-id}/

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
          image = "supabase/storage-api:v1.48.26"

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
          env {
            name = "AUTH_JWT_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.tenant_config.metadata[0].name
                key  = "JWT_SECRET"
              }
            }
          }
          env {
            name  = "DATABASE_URL"
            value = local.db_uri_storage
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
            value = "http://${var.shared_imgproxy_host}:5001"
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
              cpu    = "150m"
              memory = "384Mi"
            }
          }
        }
      }
    }
  }
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

# --- Edge Functions ---
# Per-tenant Deno edge runtime with tenant-specific function files.

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
      }

      spec {
        # Init container seeds the PVC with default edge functions on first deploy
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
                name = kubernetes_secret.tenant_config.metadata[0].name
                key  = "JWT_SECRET"
              }
            }
          }
          # Internal URL goes through the tenant router in the shared namespace
          env {
            name  = "SUPABASE_URL"
            value = local.api_url
          }
          env {
            name  = "SUPABASE_PUBLIC_URL"
            value = local.api_url
          }
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
          env {
            name = "SUPABASE_PUBLISHABLE_KEYS"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.tenant_config.metadata[0].name
                key  = "SUPABASE_PUBLISHABLE_KEY"
              }
            }
          }
          env {
            name = "SUPABASE_SECRET_KEYS"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.tenant_config.metadata[0].name
                key  = "SUPABASE_SECRET_KEY"
              }
            }
          }
          env {
            name  = "SUPABASE_DB_URL"
            value = local.db_uri_funcs
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
              cpu    = "40m"
              memory = "100Mi"
            }
            limits = {
              cpu    = "150m"
              memory = "384Mi"
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
