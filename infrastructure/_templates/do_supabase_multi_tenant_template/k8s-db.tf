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
        # For wal_g_image (DOCR injects this secret into every namespace)
        dynamic "image_pull_secrets" {
          for_each = var.image_pull_secret_name == "" ? [] : [var.image_pull_secret_name]
          content {
            name = image_pull_secrets.value
          }
        }

        # A data directory from another Postgres major can't be opened; stop
        # here with a clear message instead of crash-looping Postgres.
        init_container {
          name  = "check-postgres-major"
          image = local.postgres_image
          command = [
            "sh", "-c",
            "if [ -f /pgdata/PG_VERSION ] && [ \"$(cat /pgdata/PG_VERSION)\" != \"${local.postgres_major}\" ]; then echo \"PGDATA holds Postgres $(cat /pgdata/PG_VERSION) data but the image is Postgres ${local.postgres_major}: upgrade the data (pg_upgrade) before switching majors\"; exit 1; fi"
          ]

          volume_mount {
            name       = "db-data"
            mount_path = "/pgdata"
            sub_path   = "pgdata"
            read_only  = true
          }
        }

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

        # The supabase/postgres image doesn't ship WAL-G (and release builds are
        # glibc, the image is musl); copy the static build in.
        init_container {
          name    = "install-wal-g"
          image   = var.wal_g_image
          command = ["cp", "/wal-g", "/walg/wal-g"]

          volume_mount {
            name       = "walg"
            mount_path = "/walg"
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
          # Recorded by the baseline hook as the image that initialised the database
          env {
            name  = "STATICBOT_IMAGE"
            value = local.postgres_image
          }
          # WAL-G for archive_command
          dynamic "env" {
            for_each = local.walg_env
            content {
              name  = env.key
              value = env.value
            }
          }
          dynamic "env" {
            for_each = local.walg_secret_env
            content {
              name = env.key
              value_from {
                secret_key_ref {
                  name = kubernetes_secret.tenant_config.metadata[0].name
                  key  = env.value
                }
              }
            }
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

          # Runs after the image's migrate.sh (initdb.d runs in name order),
          # first boot only
          volume_mount {
            name       = "db-lifecycle"
            mount_path = "/docker-entrypoint-initdb.d/zz-staticbot-baseline.sh"
            sub_path   = "baseline.sh"
            read_only  = true
          }
          volume_mount {
            name       = "db-lifecycle"
            mount_path = "/staticbot"
            read_only  = true
          }

          volume_mount {
            name       = "walg"
            mount_path = "/walg"
            read_only  = true
          }

          # Continuous WAL archiving, as on Staticbot's own database: at most
          # ~60s of transactions can be lost with the volume.
          command = [
            "docker-entrypoint.sh", "postgres",
            "-c", "config_file=/etc/postgresql/postgresql.conf",
            "-c", "log_min_messages=fatal", # prevents Realtime polling queries from appearing in logs
            "-c", "archive_mode=on",
            "-c", "archive_command=/walg/wal-g wal-push %p",
            "-c", "archive_timeout=60"
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

        # Base backups, retention and the Vault key (k8s/db-lifecycle/backup.sh).
        # Same PGDATA path as Postgres: wal-g backup-push checks it.
        container {
          name    = "backup"
          image   = local.postgres_image
          command = ["bash", "/staticbot/backup.sh"]

          dynamic "env" {
            for_each = local.walg_env
            content {
              name  = env.key
              value = env.value
            }
          }
          dynamic "env" {
            for_each = local.walg_secret_env
            content {
              name = env.key
              value_from {
                secret_key_ref {
                  name = kubernetes_secret.tenant_config.metadata[0].name
                  key  = env.value
                }
              }
            }
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
            name  = "PGPORT"
            value = tostring(local.db_port)
          }
          env {
            name  = "BACKUP_INTERVAL_HOURS"
            value = tostring(var.backup_interval_hours)
          }
          env {
            name  = "BACKUP_RETAIN_FULL"
            value = tostring(var.backup_retain_full)
          }

          volume_mount {
            name       = "db-data"
            mount_path = "/var/lib/postgresql/data"
            sub_path   = "pgdata"
          }
          volume_mount {
            name       = "db-data"
            mount_path = "/etc/postgresql-custom"
            sub_path   = "postgresql-custom"
            read_only  = true
          }
          volume_mount {
            name       = "db-data"
            mount_path = "/var/lib/postgresql/backup-state"
            sub_path   = "backup-state"
          }
          volume_mount {
            name       = "db-lifecycle"
            mount_path = "/staticbot"
            read_only  = true
          }
          volume_mount {
            name       = "walg"
            mount_path = "/walg"
            read_only  = true
          }

          resources {
            requests = {
              cpu    = "20m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
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
          name = "walg"
          empty_dir {}
        }

        volume {
          name = "db-init-scripts"
          config_map {
            name = kubernetes_config_map.db_init_scripts.metadata[0].name
          }
        }

        volume {
          name = "db-lifecycle"
          config_map {
            name         = kubernetes_config_map.db_lifecycle.metadata[0].name
            default_mode = "0755" # baseline.sh is executed, not sourced, by docker-entrypoint.sh
          }
        }
      }
    }
  }

  # Registration, migrations and the API services need a running database
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

# --- Database migrations ---
# Brings the tenant database up to the current template after an image bump or
# a new template migration (k8s/db-lifecycle/migrate.sh). The job name carries
# a hash of the image and the migration inputs, so it re-runs exactly when they
# change; on a fresh database it finds everything recorded and does nothing.
# Failures fail `terraform apply`; there's no automatic retry of a migration.

locals {
  migrate_hash = substr(sha256(jsonencode([
    local.postgres_image,
    local.db_lifecycle_files,
    kubernetes_config_map.db_init_scripts.data,
  ])), 0, 8)
}

resource "kubernetes_job" "migrate_db" {
  metadata {
    name      = "migrate-db-${local.migrate_hash}"
    namespace = kubernetes_namespace.tenant.metadata[0].name
    labels    = { app = "migrate-db", "tenant-id" = var.tenant_id }
  }

  spec {
    backoff_limit = 0

    template {
      metadata {
        labels = { app = "migrate-db", "tenant-id" = var.tenant_id }
      }

      spec {
        restart_policy = "Never"

        container {
          name    = "migrate"
          image   = local.postgres_image # carries the image's migrations to apply
          command = ["bash", "/staticbot/migrate.sh"]

          env {
            name  = "PGHOST"
            value = local.db_host
          }
          env {
            name  = "PGPORT"
            value = tostring(local.db_port)
          }
          env {
            name  = "PGDATABASE"
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
            name  = "STATICBOT_IMAGE"
            value = local.postgres_image
          }

          volume_mount {
            name       = "db-lifecycle"
            mount_path = "/staticbot"
            read_only  = true
          }
          volume_mount {
            name       = "db-init-scripts"
            mount_path = "/initsql"
            read_only  = true
          }

          resources {
            requests = {
              cpu    = "20m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "256Mi"
            }
          }
        }

        volume {
          name = "db-lifecycle"
          config_map {
            name = kubernetes_config_map.db_lifecycle.metadata[0].name
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

  wait_for_completion = true

  timeouts {
    create = "15m"
  }

  depends_on = [kubernetes_deployment.db]
}
