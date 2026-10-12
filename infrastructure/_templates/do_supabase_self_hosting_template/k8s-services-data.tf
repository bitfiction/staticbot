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
        # /etc/postgresql-custom holds config the image's postgresql.conf includes
        # and the pgsodium/Vault root key. Upstream persists it in a named volume,
        # which Docker seeds from the image; a PVC starts empty, so seed it here.
        # Entries that already exist are kept, above all pgsodium_root.key:
        # losing it makes Vault secrets undecryptable. (Per-entry loop because
        # BusyBox `cp -an dir/. dest/` silently copies nothing.)
        init_container {
          name  = "init-postgresql-custom"
          image = local.postgres_image
          command = [
            "sh", "-c",
            "for f in /etc/postgresql-custom/*; do [ -e \"/persist/$(basename \"$f\")\" ] || cp -a \"$f\" /persist/; done && chown -R postgres:postgres /persist"
          ]

          volume_mount {
            name       = "db-data"
            mount_path = "/persist"
            sub_path   = "postgresql-custom"
          }
        }

        container {
          name  = "db"
          image = local.postgres_image

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
            name  = "JWT_EXP"
            value = tostring(var.jwt_expiry)
          }

          # PGDATA lives in a subdirectory: the volume root of a block-storage
          # PVC contains lost+found, and initdb refuses a non-empty directory.
          volume_mount {
            name       = "db-data"
            mount_path = "/var/lib/postgresql/data"
            sub_path   = "pgdata"
          }

          volume_mount {
            name       = "db-data"
            mount_path = "/etc/postgresql-custom"
            sub_path   = "postgresql-custom"
          }

          dynamic "volume_mount" {
            for_each = local.db_init_mounts
            content {
              name       = "db-init-scripts"
              mount_path = "/docker-entrypoint-initdb.d/${volume_mount.value}"
              sub_path   = volume_mount.key
              read_only  = true
            }
          }

          command = [
            "docker-entrypoint.sh", "postgres",
            "-c", "config_file=/etc/postgresql/postgresql.conf",
            "-c", "log_min_messages=fatal" # prevents Realtime polling queries from appearing in logs
          ]

          # First boot runs the image's init scripts and migrations before the
          # server listens on TCP; allow up to 5 minutes for that.
          startup_probe {
            exec {
              command = ["pg_isready", "-U", "postgres", "-h", "localhost"]
            }
            period_seconds    = 5
            timeout_seconds   = 5
            failure_threshold = 60
          }

          liveness_probe {
            exec {
              command = ["pg_isready", "-U", "postgres", "-h", "localhost"]
            }
            period_seconds    = 10
            timeout_seconds   = 5
            failure_threshold = 6
          }

          readiness_probe {
            exec {
              command = ["pg_isready", "-U", "postgres", "-h", "localhost"]
            }
            period_seconds    = 5
            timeout_seconds   = 5
            failure_threshold = 3
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
# Collects logs from Supabase pods via K8s log files and forwards them to
# Analytics (Logflare). kubernetes_logs only sees pods on its own node, so it
# runs on every node.

resource "kubernetes_daemonset" "vector" {
  metadata {
    name      = "vector"
    namespace = kubernetes_namespace.supabase.metadata[0].name
    labels    = { app = "vector" }
  }

  spec {
    selector {
      match_labels = { app = "vector" }
    }

    template {
      metadata {
        labels = { app = "vector" }
        annotations = {
          "checksum/config" = sha256(kubernetes_config_map.vector_config.data["vector.json"])
        }
      }

      spec {
        service_account_name = kubernetes_service_account.vector.metadata[0].name

        container {
          name  = "vector"
          image = "timberio/vector:0.53.0-alpine"

          args = ["--config", "/etc/vector/vector.json"]

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
            name = "VECTOR_SELF_NODE_NAME"
            value_from {
              field_ref {
                field_path = "spec.nodeName"
              }
            }
          }

          volume_mount {
            name       = "vector-config"
            mount_path = "/etc/vector"
            read_only  = true
          }

          volume_mount {
            name       = "pod-logs"
            mount_path = "/var/log/pods"
            read_only  = true
          }

          volume_mount {
            name       = "vector-data"
            mount_path = "/var/lib/vector"
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

        volume {
          name = "vector-config"
          config_map {
            name = kubernetes_config_map.vector_config.metadata[0].name
          }
        }

        volume {
          name = "pod-logs"
          host_path {
            path = "/var/log/pods"
            type = "Directory"
          }
        }

        volume {
          name = "vector-data"
          empty_dir {}
        }
      }
    }
  }
}
