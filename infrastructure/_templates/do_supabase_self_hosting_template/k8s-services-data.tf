# --- PostgreSQL ---
# First boot runs the image's init scripts and migrations plus upstream's
# docker/volumes/db scripts and records a schema baseline; the migrate-db Job
# upgrades it later, and WAL-G backs it up (k8s/db-lifecycle/README.md).

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
            container_port = var.postgres_port
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
                  name = kubernetes_secret.supabase_config.metadata[0].name
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
              cpu    = "500m"
              memory = "1Gi"
            }
            limits = {
              cpu    = "1000m"
              memory = "2Gi"
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
                  name = kubernetes_secret.supabase_config.metadata[0].name
                  key  = env.value
                }
              }
            }
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
            name  = "PGPORT"
            value = tostring(var.postgres_port)
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
    namespace = kubernetes_namespace.supabase.metadata[0].name
  }
  spec {
    selector = { app = "db" }
    port {
      port        = 5432
      target_port = var.postgres_port
    }
    type = "ClusterIP"
  }
}

# --- Database migrations ---
# Brings the database up to the current template after an image bump or
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
    namespace = kubernetes_namespace.supabase.metadata[0].name
    labels    = { app = "migrate-db" }
  }

  spec {
    backoff_limit = 0

    template {
      metadata {
        labels = { app = "migrate-db" }
      }

      spec {
        restart_policy = "Never"

        container {
          name    = "migrate"
          image   = local.postgres_image # carries the image's migrations to apply
          command = ["bash", "/staticbot/migrate.sh"]

          env {
            name  = "PGHOST"
            value = "db"
          }
          env {
            name  = "PGPORT"
            value = tostring(var.postgres_port)
          }
          env {
            name  = "PGDATABASE"
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
