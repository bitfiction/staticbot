resource "kubernetes_namespace" "tenant" {
  metadata {
    name = local.tenant_namespace
    labels = {
      "app.kubernetes.io/part-of"    = "supabase-multi-tenant"
      "app.kubernetes.io/managed-by" = "staticbot"
      "tenant-id"                    = var.tenant_id
    }
  }
}

# --- Kubernetes Secret: tenant-specific credentials ---

resource "kubernetes_secret" "tenant_config" {
  metadata {
    name      = "supabase-tenant-config"
    namespace = kubernetes_namespace.tenant.metadata[0].name
  }

  data = {
    JWT_SECRET                    = var.jwt_secret
    ANON_KEY                      = var.anon_key
    SERVICE_ROLE_KEY              = var.service_role_key
    POSTGRES_PASSWORD             = var.postgres_password
    SUPABASE_PUBLISHABLE_KEY      = var.supabase_publishable_key
    SUPABASE_SECRET_KEY           = var.supabase_secret_key
    ANON_KEY_ASYMMETRIC           = var.anon_key_asymmetric
    SERVICE_ROLE_KEY_ASYMMETRIC   = var.service_role_key_asymmetric
    SMTP_PASS                     = var.smtp_pass
    SPACES_ACCESS_KEY             = var.spaces_access_key
    SPACES_SECRET_KEY             = var.spaces_secret_key
    S3_PROTOCOL_ACCESS_KEY_ID     = var.s3_protocol_access_key_id
    S3_PROTOCOL_ACCESS_KEY_SECRET = var.s3_protocol_access_key_secret
  }
}

# --- PVC: Edge Functions data (per-tenant) ---

resource "kubernetes_persistent_volume_claim" "functions_data" {
  metadata {
    name      = "functions-data"
    namespace = kubernetes_namespace.tenant.metadata[0].name
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "do-block-storage"
    resources {
      requests = {
        storage = "1Gi"
      }
    }
  }
}

# --- ConfigMap: Edge Functions default files ---

resource "kubernetes_config_map" "functions_init" {
  metadata {
    name      = "functions-init"
    namespace = kubernetes_namespace.tenant.metadata[0].name
  }

  data = {
    "main-index.ts"  = file("${path.module}/docker/volumes/functions/main/index.ts")
    "hello-index.ts" = file("${path.module}/docker/volumes/functions/hello/index.ts")
  }
}
