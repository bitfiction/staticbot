# --- Realtime + Supavisor Tenant Registration ---
# Upserts this tenant into the shared Realtime and Supavisor services through
# their management APIs (k8s/register-tenant.py). The tenant's database
# initialises itself on first boot, so no database provisioning job is needed.
#
# The job name carries a hash of everything it registers, so a changed
# password or JWT secret replaces the job and re-registers the tenant.
# Failures fail `terraform apply` instead of being logged as warnings.

locals {
  registration_hash = substr(sha256(jsonencode([
    var.tenant_id,
    var.postgres_password,
    var.jwt_secret,
    var.jwt_jwks,
    var.pooler_default_pool_size,
    var.pooler_max_client_conn,
    file("${path.module}/k8s/register-tenant.py"),
  ])), 0, 8)
}

resource "kubernetes_config_map" "register_tenant" {
  metadata {
    name      = "register-tenant"
    namespace = kubernetes_namespace.tenant.metadata[0].name
  }

  data = {
    "register-tenant.py" = file("${path.module}/k8s/register-tenant.py")
  }
}

resource "kubernetes_job" "register_services" {
  metadata {
    name      = "register-services-${local.registration_hash}"
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
        restart_policy = "Never"

        container {
          name    = "register"
          image   = "python:3.13-alpine"
          command = ["python", "-I", "/job/register-tenant.py"]

          env {
            name  = "TENANT_ID"
            value = var.tenant_id
          }
          env {
            name  = "TENANT_DB_HOST"
            value = local.db_fqdn
          }
          env {
            name  = "TENANT_DB_PORT"
            value = tostring(local.db_port)
          }
          env {
            name  = "TENANT_DB_NAME"
            value = local.db_name
          }
          env {
            name = "TENANT_DB_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.tenant_config.metadata[0].name
                key  = "POSTGRES_PASSWORD"
              }
            }
          }
          env {
            name = "TENANT_JWT_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.tenant_config.metadata[0].name
                key  = "JWT_SECRET"
              }
            }
          }
          env {
            name = "TENANT_JWT_JWKS"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.tenant_config.metadata[0].name
                key  = "JWT_JWKS"
              }
            }
          }
          env {
            name = "SHARED_API_JWT_SECRET"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.tenant_config.metadata[0].name
                key  = "SHARED_API_JWT_SECRET"
              }
            }
          }
          env {
            name  = "REALTIME_URL"
            value = "http://${local.realtime_host}:4000"
          }
          env {
            name  = "SUPAVISOR_URL"
            value = "http://${local.supavisor_host}:4000"
          }
          env {
            name  = "POOLER_DEFAULT_POOL_SIZE"
            value = tostring(var.pooler_default_pool_size)
          }
          env {
            name  = "POOLER_MAX_CLIENT_CONN"
            value = tostring(var.pooler_max_client_conn)
          }

          volume_mount {
            name       = "script"
            mount_path = "/job"
            read_only  = true
          }

          resources {
            requests = {
              cpu    = "10m"
              memory = "32Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "128Mi"
            }
          }
        }

        volume {
          name = "script"
          config_map {
            name = kubernetes_config_map.register_tenant.metadata[0].name
          }
        }
      }
    }
  }

  wait_for_completion = true

  timeouts {
    create = "5m"
  }

  depends_on = [kubernetes_deployment.db]
}
