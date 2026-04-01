# --- PostgreSQL ---

resource "kubernetes_deployment" "db" {
  metadata {
    name      = "db"
    namespace = kubernetes_namespace.supabase.metadata[0].name
    labels    = { app = "db" }
  }

  spec {
    replicas = 1
    strategy {
      type = "Recreate" # PVC is ReadWriteOnce
    }
    selector {
      match_labels = { app = "db" }
    }

    template {
      metadata {
        labels = { app = "db" }
      }

      spec {
        container {
          name  = "db"
          image = "supabase/postgres:15.8.1.085"

          port {
            container_port = 5432
            protocol       = "TCP"
          }

          env {
            name  = "POSTGRES_HOST"
            value = "/var/run/postgresql"
          }
          env {
            name  = "PGPORT"
            value = tostring(var.postgres_port)
          }
          env {
            name  = "POSTGRES_PORT"
            value = tostring(var.postgres_port)
          }
          env {
            name  = "PGDATABASE"
            value = var.postgres_db
          }
          env {
            name  = "POSTGRES_DB"
            value = var.postgres_db
          }
          env {
            name = "PGPASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.supabase_config.metadata[0].name
                key  = "POSTGRES_PASSWORD"
              }
            }
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
            name = "JWT_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.supabase_config.metadata[0].name
                key  = "JWT_SECRET"
              }
            }
          }
          env {
            name  = "JWT_EXP"
            value = tostring(var.jwt_expiry)
          }

          # PostgreSQL data volume
          volume_mount {
            name       = "db-data"
            mount_path = "/var/lib/postgresql/data"
          }

          # SQL init scripts from ConfigMap
          volume_mount {
            name       = "db-init-scripts"
            mount_path = "/docker-entrypoint-initdb.d/migrations"
          }

          command = [
            "docker-entrypoint.sh", "postgres",
            "-c", "config_file=/etc/postgresql/postgresql.conf",
            "-c", "log_min_messages=fatal"
          ]

          liveness_probe {
            exec {
              command = ["pg_isready", "-U", "postgres", "-h", "localhost"]
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 6
          }

          readiness_probe {
            exec {
              command = ["pg_isready", "-U", "postgres", "-h", "localhost"]
            }
            initial_delay_seconds = 5
            period_seconds        = 5
            timeout_seconds       = 5
            failure_threshold     = 3
          }

          resources {
            requests = {
              cpu    = "500m"
              memory = "1Gi"
            }
            limits = {
              cpu    = "1000m"
              memory = "2Gi"
            }
          }
        }

        volume {
          name = "db-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.db_data.metadata[0].name
          }
        }

        volume {
          name = "db-init-scripts"
          config_map {
            name = kubernetes_config_map.db_init_scripts.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "db" {
  metadata {
    name      = "db"
    namespace = kubernetes_namespace.supabase.metadata[0].name
  }
  spec {
    selector = { app = "db" }
    port {
      port        = 5432
      target_port = 5432
    }
    type = "ClusterIP"
  }
}

# --- Vector (Log Processing) ---
# Simplified for K8s — collects logs from containers and routes to analytics.
# In K8s, containers log to stdout and logs are available via kubectl logs.
# Vector here primarily serves as the log forwarder to the analytics (Logflare) service.

resource "kubernetes_deployment" "vector" {
  metadata {
    name      = "vector"
    namespace = kubernetes_namespace.supabase.metadata[0].name
    labels    = { app = "vector" }
  }

  spec {
    replicas = 1
    selector {
      match_labels = { app = "vector" }
    }

    template {
      metadata {
        labels = { app = "vector" }
      }

      spec {
        container {
          name  = "vector"
          image = "timberio/vector:0.53.0-alpine"

          env {
            name = "LOGFLARE_PUBLIC_ACCESS_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.supabase_config.metadata[0].name
                key  = "LOGFLARE_PUBLIC_ACCESS_TOKEN"
              }
            }
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 9001
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
              cpu    = "200m"
              memory = "256Mi"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "vector" {
  metadata {
    name      = "vector"
    namespace = kubernetes_namespace.supabase.metadata[0].name
  }
  spec {
    selector = { app = "vector" }
    port {
      port        = 9001
      target_port = 9001
    }
    type = "ClusterIP"
  }
}
