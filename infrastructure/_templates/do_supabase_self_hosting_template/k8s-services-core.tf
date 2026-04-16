# --- Auth (GoTrue) ---

resource "kubernetes_deployment" "auth" {
  metadata {
    name      = "auth"
    namespace = kubernetes_namespace.supabase.metadata[0].name
    labels    = { app = "auth" }
  }

  spec {
    replicas = 1
    selector {
      match_labels = { app = "auth" }
    }

    template {
      metadata {
        labels = { app = "auth" }
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
            value = var.api_external_url
          }
          env {
            name  = "GOTRUE_DB_DRIVER"
            value = "postgres"
          }
          env {
            name  = "GOTRUE_DB_DATABASE_URL"
            value = "postgres://supabase_auth_admin:${var.postgres_password}@db:${var.postgres_port}/${var.postgres_db}"
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
                name = kubernetes_secret.supabase_config.metadata[0].name
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
                name = kubernetes_secret.supabase_config.metadata[0].name
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

resource "kubernetes_service" "auth" {
  metadata {
    name      = "auth"
    namespace = kubernetes_namespace.supabase.metadata[0].name
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
    namespace = kubernetes_namespace.supabase.metadata[0].name
    labels    = { app = "rest" }
  }

  spec {
    replicas = 1
    selector {
      match_labels = { app = "rest" }
    }

    template {
      metadata {
        labels = { app = "rest" }
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
            value = "postgres://authenticator:${var.postgres_password}@db:${var.postgres_port}/${var.postgres_db}"
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
                name = kubernetes_secret.supabase_config.metadata[0].name
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
                name = kubernetes_secret.supabase_config.metadata[0].name
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

resource "kubernetes_service" "rest" {
  metadata {
    name      = "rest"
    namespace = kubernetes_namespace.supabase.metadata[0].name
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

# --- Realtime ---

resource "kubernetes_deployment" "realtime" {
  metadata {
    name      = "realtime"
    namespace = kubernetes_namespace.supabase.metadata[0].name
    labels    = { app = "realtime" }
  }

  spec {
    replicas = 1
    selector {
      match_labels = { app = "realtime" }
    }

    template {
      metadata {
        labels = { app = "realtime" }
      }

      spec {
        container {
          name  = "realtime"
          image = "supabase/realtime:v2.76.5"

          port {
            container_port = 4000
            protocol       = "TCP"
          }

          env {
            name  = "PORT"
            value = "4000"
          }
          env {
            name  = "DB_HOST"
            value = "db"
          }
          env {
            name  = "DB_PORT"
            value = tostring(var.postgres_port)
          }
          env {
            name  = "DB_USER"
            value = "supabase_admin"
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
            name  = "DB_NAME"
            value = var.postgres_db
          }
          env {
            name  = "DB_AFTER_CONNECT_QUERY"
            value = "SET search_path TO _realtime"
          }
          env {
            name  = "DB_ENC_KEY"
            value = "supabaserealtime"
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
            name = "SECRET_KEY_BASE"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.supabase_config.metadata[0].name
                key  = "SECRET_KEY_BASE"
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
            name  = "ERL_AFLAGS"
            value = "-proto_dist inet_tcp"
          }
          env {
            name  = "DNS_NODES"
            value = "''"
          }
          env {
            name  = "RLIMIT_NOFILE"
            value = "10000"
          }
          env {
            name  = "APP_NAME"
            value = "realtime"
          }
          env {
            name  = "SEED_SELF_HOST"
            value = "true"
          }
          env {
            name  = "RUN_JANITOR"
            value = "true"
          }
          env {
            name  = "DISABLE_HEALTHCHECK_LOGGING"
            value = "true"
          }

          liveness_probe {
            http_get {
              path = "/api/tenants/realtime-dev/health"
              port = 4000
              http_header {
                name  = "Authorization"
                value = "Bearer ${var.anon_key}"
              }
            }
            initial_delay_seconds = 15
            period_seconds        = 30
            timeout_seconds       = 5
            failure_threshold     = 3
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

resource "kubernetes_service" "realtime" {
  metadata {
    name      = "realtime"
    namespace = kubernetes_namespace.supabase.metadata[0].name
  }
  spec {
    selector = { app = "realtime" }
    port {
      port        = 4000
      target_port = 4000
    }
    type = "ClusterIP"
  }
}

# --- Storage + ImgProxy (shared pod — DO Block Storage is ReadWriteOnce) ---

resource "kubernetes_deployment" "storage" {
  metadata {
    name      = "storage"
    namespace = kubernetes_namespace.supabase.metadata[0].name
    labels    = { app = "storage" }
  }

  spec {
    replicas = 1
    strategy {
      type = "Recreate" # PVC is ReadWriteOnce
    }
    selector {
      match_labels = { app = "storage" }
    }

    template {
      metadata {
        labels = { app = "storage" }
      }

      spec {
        # Storage API container
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
                name = kubernetes_secret.supabase_config.metadata[0].name
                key  = "ANON_KEY"
              }
            }
          }
          env {
            name = "SERVICE_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.supabase_config.metadata[0].name
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
                name = kubernetes_secret.supabase_config.metadata[0].name
                key  = "JWT_SECRET"
              }
            }
          }
          env {
            name  = "DATABASE_URL"
            value = "postgres://supabase_storage_admin:${var.postgres_password}@db:${var.postgres_port}/${var.postgres_db}"
          }
          env {
            name  = "STORAGE_PUBLIC_URL"
            value = var.supabase_public_url
          }
          env {
            name  = "REQUEST_ALLOW_X_FORWARDED_PATH"
            value = "true"
          }
          env {
            name  = "FILE_SIZE_LIMIT"
            value = "52428800"
          }
          env {
            name  = "STORAGE_BACKEND"
            value = "file"
          }
          env {
            name  = "GLOBAL_S3_BUCKET"
            value = var.storage_s3_bucket
          }
          env {
            name  = "FILE_STORAGE_BACKEND_PATH"
            value = "/var/lib/storage"
          }
          env {
            name  = "TENANT_ID"
            value = var.storage_tenant_id
          }
          env {
            name  = "REGION"
            value = var.storage_region
          }
          env {
            name  = "ENABLE_IMAGE_TRANSFORMATION"
            value = "true"
          }
          env {
            name  = "IMGPROXY_URL"
            value = "http://localhost:5001" # ImgProxy runs in the same pod
          }
          env {
            name = "S3_PROTOCOL_ACCESS_KEY_ID"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.supabase_config.metadata[0].name
                key  = "S3_PROTOCOL_ACCESS_KEY_ID"
              }
            }
          }
          env {
            name = "S3_PROTOCOL_ACCESS_KEY_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.supabase_config.metadata[0].name
                key  = "S3_PROTOCOL_ACCESS_KEY_SECRET"
              }
            }
          }

          volume_mount {
            name       = "storage-data"
            mount_path = "/var/lib/storage"
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
              cpu    = "200m"
              memory = "512Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "1Gi"
            }
          }
        }

        # ImgProxy container (same pod, shares storage PVC)
        container {
          name  = "imgproxy"
          image = "darthsim/imgproxy:v3.30.1"

          port {
            container_port = 5001
            protocol       = "TCP"
          }

          env {
            name  = "IMGPROXY_BIND"
            value = ":5001"
          }
          env {
            name  = "IMGPROXY_LOCAL_FILESYSTEM_ROOT"
            value = "/"
          }
          env {
            name  = "IMGPROXY_USE_ETAG"
            value = "true"
          }
          env {
            name  = "IMGPROXY_AUTO_WEBP"
            value = tostring(var.imgproxy_enable_webp_detection)
          }
          env {
            name  = "IMGPROXY_MAX_SRC_RESOLUTION"
            value = "16.8"
          }

          volume_mount {
            name       = "storage-data"
            mount_path = "/var/lib/storage"
          }

          liveness_probe {
            exec {
              command = ["imgproxy", "health"]
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
              cpu    = "300m"
              memory = "512Mi"
            }
          }
        }

        volume {
          name = "storage-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.storage_data.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "storage" {
  metadata {
    name      = "storage"
    namespace = kubernetes_namespace.supabase.metadata[0].name
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

# ImgProxy service — exposed for direct access if needed, but primarily
# accessed via localhost within the shared pod by the storage container.
resource "kubernetes_service" "imgproxy" {
  metadata {
    name      = "imgproxy"
    namespace = kubernetes_namespace.supabase.metadata[0].name
  }
  spec {
    selector = { app = "storage" } # Same pod as storage
    port {
      port        = 5001
      target_port = 5001
    }
    type = "ClusterIP"
  }
}
