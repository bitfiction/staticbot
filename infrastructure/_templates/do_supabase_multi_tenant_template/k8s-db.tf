# --- PostgreSQL (tenant-owned) ---
# Each tenant runs its own Postgres, so roles, passwords, extensions, pg_net,
# pg_cron and Vault are isolated per tenant, exactly as on a single-tenant
# deployment. First boot runs the image's init scripts and migrations plus
# upstream's docker/volumes/db scripts.

resource "kubernetes_deployment" "db" {
  metadata {
    name      = "db"
    namespace = kubernetes_namespace.tenant.metadata[0].name
    labels    = { app = "db", "tenant-id" = var.tenant_id }
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
        labels = { app = "db", "tenant-id" = var.tenant_id }
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
            container_port = local.db_port
            protocol       = "TCP"
          }

          env {
            name  = "POSTGRES_HOST"
            value = "/var/run/postgresql"
          }
          env {
            name  = "PGPORT"
            value = tostring(local.db_port)
          }
          env {
            name  = "POSTGRES_PORT"
            value = tostring(local.db_port)
          }
          env {
            name  = "PGDATABASE"
            value = local.db_name
          }
          env {
            name  = "POSTGRES_DB"
            value = local.db_name
          }
          env {
            name = "PGPASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.tenant_config.metadata[0].name
                key  = "POSTGRES_PASSWORD"
              }
            }
          }
          env {
            name = "POSTGRES_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.tenant_config.metadata[0].name
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
              cpu    = "100m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "1Gi"
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

  # Registration and the API services need a running database
  wait_for_rollout = true
}

resource "kubernetes_service" "db" {
  metadata {
    name      = "db"
    namespace = kubernetes_namespace.tenant.metadata[0].name
  }
  spec {
    selector = { app = "db" }
    port {
      port        = local.db_port
      target_port = local.db_port
    }
    type = "ClusterIP"
  }
}
