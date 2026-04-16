# --- Tenant Database Provisioning ---
# Kubernetes Job that runs on terraform apply to:
# 1. CREATE DATABASE tenant_{id} if not exists
# 2. Run Supabase init SQL scripts against the new database
# 3. Set per-tenant JWT secret on the database
#
# This Job is idempotent — safe to re-run on subsequent applies.

resource "kubernetes_job" "provision_db" {
  metadata {
    name      = "provision-db-${var.tenant_id}"
    namespace = kubernetes_namespace.tenant.metadata[0].name
    labels    = { app = "provision-db", "tenant-id" = var.tenant_id }
  }

  spec {
    backoff_limit = 3

    template {
      metadata {
        labels = { app = "provision-db", "tenant-id" = var.tenant_id }
      }

      spec {
        restart_policy = "OnFailure"

        container {
          name  = "provision"
          image = "supabase/postgres:15.8.1.085"

          command = ["bash", "-c", <<-SCRIPT
            set -euo pipefail

            PGHOST="${var.shared_db_host}"
            PGPORT="${var.shared_db_port}"
            PGUSER="postgres"
            export PGPASSWORD="$DB_PASSWORD"
            TENANT_DB="tenant_${var.tenant_id}"

            echo "=== Provisioning database: $TENANT_DB ==="

            # 1. Create database if not exists
            if psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -lqt | cut -d \| -f 1 | grep -qw "$TENANT_DB"; then
              echo "Database $TENANT_DB already exists, skipping creation"
            else
              echo "Creating database $TENANT_DB..."
              psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -c "CREATE DATABASE \"$TENANT_DB\" OWNER postgres;"
            fi

            # 2. Run init SQL scripts against the tenant database
            # Order matters: roles & extensions first, then schemas
            for script in /init-scripts/97-_supabase.sql /init-scripts/98-webhooks.sql /init-scripts/99-roles.sql /init-scripts/99-jwt.sql /init-scripts/99-realtime.sql /init-scripts/99-logs.sql /init-scripts/99-pooler.sql; do
              if [ -f "$script" ]; then
                echo "Running $(basename $script)..."
                psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$TENANT_DB" -f "$script" 2>&1 || true
              fi
            done

            # 3. Set per-tenant JWT secret
            echo "Setting JWT secret for $TENANT_DB..."
            psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$TENANT_DB" -c "ALTER DATABASE \"$TENANT_DB\" SET \"app.settings.jwt_secret\" TO '$JWT_SECRET';"

            # 4. Set connection limit per tenant to prevent noisy neighbor
            psql -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -c "ALTER DATABASE \"$TENANT_DB\" CONNECTION LIMIT 50;"

            echo "=== Database provisioning complete ==="
          SCRIPT
          ]

          env {
            name = "DB_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.tenant_config.metadata[0].name
                key  = "POSTGRES_PASSWORD"
              }
            }
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

          volume_mount {
            name       = "init-scripts"
            mount_path = "/init-scripts"
            read_only  = true
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
          }
        }

        volume {
          name = "init-scripts"
          config_map {
            name = kubernetes_config_map.db_init_scripts.metadata[0].name
          }
        }
      }
    }
  }

  wait_for_completion = true

  timeouts {
    create = "5m"
  }
}

# --- DB Init Scripts ConfigMap ---
# Same Supabase init scripts, mounted into the provisioning job.

resource "kubernetes_config_map" "db_init_scripts" {
  metadata {
    name      = "db-init-scripts"
    namespace = kubernetes_namespace.tenant.metadata[0].name
  }

  data = {
    "97-_supabase.sql" = file("${path.module}/docker/volumes/db/_supabase.sql")
    "98-webhooks.sql"  = file("${path.module}/docker/volumes/db/webhooks.sql")
    "99-roles.sql"     = file("${path.module}/docker/volumes/db/roles.sql")
    "99-jwt.sql"       = file("${path.module}/docker/volumes/db/jwt.sql")
    "99-realtime.sql"  = file("${path.module}/docker/volumes/db/realtime.sql")
    "99-logs.sql"      = file("${path.module}/docker/volumes/db/logs.sql")
    "99-pooler.sql"    = file("${path.module}/docker/volumes/db/pooler.sql")
  }
}

# --- Realtime + Supavisor Tenant Registration ---
# Registers the tenant with the shared Realtime and Supavisor services via their APIs.

resource "kubernetes_job" "register_services" {
  metadata {
    name      = "register-services-${var.tenant_id}"
    namespace = kubernetes_namespace.tenant.metadata[0].name
    labels    = { app = "register-services", "tenant-id" = var.tenant_id }
  }

  spec {
    backoff_limit = 3

    template {
      metadata {
        labels = { app = "register-services", "tenant-id" = var.tenant_id }
      }

      spec {
        restart_policy = "OnFailure"

        container {
          name  = "register"
          image = "curlimages/curl:8.5.0"

          command = ["sh", "-c", <<-SCRIPT
            set -euo pipefail

            REALTIME_HOST="realtime.${var.shared_namespace}.svc.cluster.local"
            SUPAVISOR_HOST="supavisor.${var.shared_namespace}.svc.cluster.local"
            DB_HOST="${var.shared_db_host}"
            DB_PORT="${var.shared_db_port}"
            TENANT_DB="tenant_${var.tenant_id}"
            TENANT_ID="${var.tenant_id}"

            echo "=== Registering tenant $TENANT_ID with shared services ==="

            # 1. Register with Realtime
            echo "Registering with Realtime..."
            HTTP_CODE=$(curl -s -o /dev/null -w "%%{http_code}" \
              -X POST "http://$REALTIME_HOST:4000/api/tenants" \
              -H "Content-Type: application/json" \
              -H "Authorization: Bearer $JWT_SECRET" \
              -d "{
                \"tenant\": {
                  \"external_id\": \"$TENANT_ID\",
                  \"name\": \"$TENANT_ID\",
                  \"extensions\": [{
                    \"type\": \"postgres_cdc_rls\",
                    \"settings\": {
                      \"db_host\": \"$DB_HOST\",
                      \"db_port\": \"$DB_PORT\",
                      \"db_name\": \"$TENANT_DB\",
                      \"db_user\": \"supabase_admin\",
                      \"db_password\": \"$DB_PASSWORD\",
                      \"region\": \"local\",
                      \"poll_interval_ms\": 100,
                      \"poll_max_record_bytes\": 1048576
                    }
                  }],
                  \"jwt_secret\": \"$JWT_SECRET\"
                }
              }" 2>&1)

            if [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "409" ]; then
              echo "Realtime registration OK (HTTP $HTTP_CODE)"
            else
              echo "WARNING: Realtime registration returned HTTP $HTTP_CODE (may already exist)"
            fi

            # 2. Register with Supavisor
            echo "Registering with Supavisor..."
            HTTP_CODE=$(curl -s -o /dev/null -w "%%{http_code}" \
              -X PUT "http://$SUPAVISOR_HOST:4000/api/tenants/$TENANT_ID" \
              -H "Content-Type: application/json" \
              -H "Authorization: Bearer $JWT_SECRET" \
              -d "{
                \"tenant\": {
                  \"external_id\": \"$TENANT_ID\",
                  \"db_host\": \"$DB_HOST\",
                  \"db_port\": $DB_PORT,
                  \"db_database\": \"$TENANT_DB\",
                  \"require_user\": false,
                  \"auth_query\": \"SELECT * FROM pgbouncer.get_auth(\$1)\",
                  \"default_max_clients\": 50,
                  \"default_pool_size\": 10,
                  \"users\": [{
                    \"db_user\": \"pgbouncer\",
                    \"db_password\": \"$DB_PASSWORD\",
                    \"mode_type\": \"transaction\",
                    \"pool_size\": 10,
                    \"is_manager\": true
                  }]
                }
              }" 2>&1)

            if [ "$HTTP_CODE" = "201" ] || [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "409" ]; then
              echo "Supavisor registration OK (HTTP $HTTP_CODE)"
            else
              echo "WARNING: Supavisor registration returned HTTP $HTTP_CODE (may already exist)"
            fi

            echo "=== Service registration complete ==="
          SCRIPT
          ]

          env {
            name = "DB_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.tenant_config.metadata[0].name
                key  = "POSTGRES_PASSWORD"
              }
            }
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

          resources {
            requests = {
              cpu    = "10m"
              memory = "32Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "64Mi"
            }
          }
        }
      }
    }
  }

  wait_for_completion = true

  timeouts {
    create = "3m"
  }

  depends_on = [kubernetes_job.provision_db]
}
