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
    JWT_SECRET                  = var.jwt_secret
    ANON_KEY                    = var.anon_key
    SERVICE_ROLE_KEY            = var.service_role_key
    POSTGRES_PASSWORD           = var.postgres_password
    SUPABASE_PUBLISHABLE_KEY    = var.supabase_publishable_key
    SUPABASE_SECRET_KEY         = var.supabase_secret_key
    ANON_KEY_ASYMMETRIC         = var.anon_key_asymmetric
    SERVICE_ROLE_KEY_ASYMMETRIC = var.service_role_key_asymmetric
    # Edge Functions expect JSON maps of named keys, as in upstream docker-compose.yml
    SUPABASE_PUBLISHABLE_KEYS = jsonencode({ default = var.supabase_publishable_key })
    SUPABASE_SECRET_KEYS      = jsonencode({ default = var.supabase_secret_key })
    # PostgREST accepts a symmetric secret or a JWKS; prefer the JWKS when set
    PGRST_JWT_SECRET              = var.jwt_jwks != "" ? var.jwt_jwks : var.jwt_secret
    JWT_KEYS                      = var.jwt_keys
    JWT_JWKS                      = var.jwt_jwks
    DASHBOARD_PASSWORD            = local.dashboard_password
    SMTP_PASS                     = var.smtp_pass
    SPACES_ACCESS_KEY             = var.spaces_access_key
    SPACES_SECRET_KEY             = var.spaces_secret_key
    S3_PROTOCOL_ACCESS_KEY_ID     = var.s3_protocol_access_key_id
    S3_PROTOCOL_ACCESS_KEY_SECRET = var.s3_protocol_access_key_secret
    SHARED_API_JWT_SECRET         = var.shared_api_jwt_secret
    BACKUP_S3_ACCESS_KEY_ID       = var.backup_s3_access_key_id
    BACKUP_S3_SECRET_ACCESS_KEY   = var.backup_s3_secret_access_key
  }
}


# --- ConfigMap: DB init SQL scripts ---
# Each file is mounted individually (sub_path) into the directory upstream's
# docker-compose.yml uses, next to the image's own init-scripts/ and migrations/.
# Mounting the ConfigMap over a whole directory would hide the image's files.

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

locals {
  # ConfigMap key → path under /docker-entrypoint-initdb.d/, as in upstream docker-compose.yml
  db_init_mounts = {
    "97-_supabase.sql" = "migrations/97-_supabase.sql"
    "98-webhooks.sql"  = "init-scripts/98-webhooks.sql"
    "99-roles.sql"     = "init-scripts/99-roles.sql"
    "99-jwt.sql"       = "init-scripts/99-jwt.sql"
    "99-realtime.sql"  = "migrations/99-realtime.sql"
    "99-logs.sql"      = "migrations/99-logs.sql"
    "99-pooler.sql"    = "migrations/99-pooler.sql"
  }
}

# --- ConfigMap: database lifecycle (k8s/db-lifecycle) ---
# baseline.sh records the schema baseline at first boot; migrate.sh (the
# migrate-db Job) upgrades existing databases. See k8s/db-lifecycle/README.md.

locals {
  db_lifecycle_dir = "${path.module}/k8s/db-lifecycle"

  db_template_migrations = {
    for f in fileset("${local.db_lifecycle_dir}/migrations", "*.sql") :
    f => file("${local.db_lifecycle_dir}/migrations/${f}")
  }

  db_lifecycle_files = merge({
    "_schema.sql"          = file("${local.db_lifecycle_dir}/_schema.sql")
    "baseline.sh"          = file("${local.db_lifecycle_dir}/baseline.sh")
    "migrate.sh"           = file("${local.db_lifecycle_dir}/migrate.sh")
    "backup.sh"            = file("${local.db_lifecycle_dir}/backup.sh")
    "restore.sh"           = file("${local.db_lifecycle_dir}/restore.sh")
    "image-migrations.txt" = file("${local.db_lifecycle_dir}/image-migrations.txt")
    # ConfigMap key → path of the upstream init SQL, for migrate.sh's drift report
    "init-mounts.txt" = join("", [for k, v in local.db_init_mounts : "${k} ${v}\n"])
  }, local.db_template_migrations)
}

resource "kubernetes_config_map" "db_lifecycle" {
  metadata {
    name      = "db-lifecycle"
    namespace = kubernetes_namespace.tenant.metadata[0].name
  }

  data = local.db_lifecycle_files

  lifecycle {
    precondition {
      # migrate.sh only picks up files matching [0-9]*.sql, in name order
      condition     = alltrue([for f in keys(local.db_template_migrations) : can(regex("^[0-9]{14}_[a-z0-9_]+\\.sql$", f))])
      error_message = "Template migrations in k8s/db-lifecycle/migrations must be named <14-digit UTC timestamp>_<description>.sql."
    }
  }
}

# --- ConfigMap: Envoy API gateway config ---
# Upstream's Envoy config with two changes for the shared Realtime:
# - its cluster points at the Realtime service in the shared namespace;
# - the Host header rewrite carries this tenant's ID, because Realtime derives
#   the tenant from the first label of the Host header.
# There is no per-tenant Studio, so its routes answer 503 behind basic auth.

resource "kubernetes_config_map" "envoy_config" {
  metadata {
    name      = "envoy-config"
    namespace = kubernetes_namespace.tenant.metadata[0].name
  }

  data = {
    "envoy.yaml" = file("${path.module}/docker/volumes/api/envoy/envoy.yaml")
    "cds.yaml" = replace(
      file("${path.module}/docker/volumes/api/envoy/cds.yaml"),
      "address: realtime-dev.supabase-realtime",
      "address: ${local.realtime_host}"
    )
    "lds.template.yaml" = replace(
      file("${path.module}/docker/volumes/api/envoy/lds.template.yaml"),
      "host_rewrite_literal: realtime-dev.supabase-realtime",
      "host_rewrite_literal: ${var.tenant_id}.realtime.${var.shared_namespace}"
    )
    "docker-entrypoint.sh" = file("${path.module}/docker/volumes/api/envoy/docker-entrypoint.sh")
  }
}

# --- ConfigMap: Edge Functions default files ---
# Copied into the functions PVC by an init container on every start.

resource "kubernetes_config_map" "functions_init" {
  metadata {
    name      = "functions-init"
    namespace = kubernetes_namespace.tenant.metadata[0].name
  }

  data = {
    "main-index.ts"  = file("${path.module}/docker/volumes/functions/main/index.ts")
    "hello-index.ts" = file("${path.module}/docker/volumes/functions/hello/index.ts")
    "deno.jsonc"     = file("${path.module}/docker/volumes/functions/deno.jsonc")
  }
}

# --- PVCs (DO Block Storage) ---

resource "kubernetes_persistent_volume_claim" "db_data" {
  metadata {
    name      = "db-data"
    namespace = kubernetes_namespace.tenant.metadata[0].name
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "do-block-storage"
    resources {
      requests = {
        storage = var.db_storage_size
      }
    }
  }
}

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

# --- Network isolation ---
# Tenant pods accept traffic only from their own namespace and from the shared
# services (tenant router, Realtime, Supavisor). Other tenants' workloads,
# including their Edge Functions, can't reach this tenant's database or APIs
# except through the public gateway.

resource "kubernetes_network_policy" "tenant_isolation" {
  metadata {
    name      = "tenant-isolation"
    namespace = kubernetes_namespace.tenant.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress"]

    ingress {
      from {
        pod_selector {}
      }
      from {
        namespace_selector {
          match_labels = { "kubernetes.io/metadata.name" = var.shared_namespace }
        }
      }
    }
  }
}
