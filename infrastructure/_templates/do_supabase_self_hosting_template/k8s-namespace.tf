resource "kubernetes_namespace" "supabase" {
  metadata {
    name = local.k8s_namespace
  }
}

# --- Kubernetes Secret: all sensitive Supabase configuration ---

resource "kubernetes_secret" "supabase_config" {
  metadata {
    name      = "supabase-config"
    namespace = kubernetes_namespace.supabase.metadata[0].name
  }

  data = {
    POSTGRES_PASSWORD             = var.postgres_password
    JWT_SECRET                    = var.jwt_secret
    ANON_KEY                      = var.anon_key
    SERVICE_ROLE_KEY              = var.service_role_key
    DASHBOARD_PASSWORD            = var.dashboard_password
    PG_META_CRYPTO_KEY            = var.pg_meta_crypto_key
    SECRET_KEY_BASE               = var.secret_key_base
    VAULT_ENC_KEY                 = var.vault_enc_key
    REALTIME_DB_ENC_KEY           = var.realtime_db_enc_key
    LOGFLARE_PUBLIC_ACCESS_TOKEN  = var.logflare_public_access_token
    LOGFLARE_PRIVATE_ACCESS_TOKEN = var.logflare_private_access_token
    SUPABASE_PUBLISHABLE_KEY      = var.supabase_publishable_key
    SUPABASE_SECRET_KEY           = var.supabase_secret_key
    ANON_KEY_ASYMMETRIC           = var.anon_key_asymmetric
    SERVICE_ROLE_KEY_ASYMMETRIC   = var.service_role_key_asymmetric
    # Edge Functions expect JSON maps of named keys, as in upstream docker-compose.yml
    SUPABASE_PUBLISHABLE_KEYS = jsonencode({ default = var.supabase_publishable_key })
    SUPABASE_SECRET_KEYS      = jsonencode({ default = var.supabase_secret_key })
    # PostgREST accepts a symmetric secret or a JWKS; prefer the JWKS when set
    PGRST_JWT_SECRET              = var.jwt_jwks != "" ? var.jwt_jwks : var.jwt_secret
    JWT_KEYS                      = var.jwt_keys
    JWT_JWKS                      = var.jwt_jwks
    SMTP_PASS                     = var.smtp_pass != null ? var.smtp_pass : ""
    S3_PROTOCOL_ACCESS_KEY_ID     = var.s3_protocol_access_key_id
    S3_PROTOCOL_ACCESS_KEY_SECRET = var.s3_protocol_access_key_secret
    OPENAI_API_KEY                = var.openai_api_key
  }
}

# --- ConfigMap: DB init SQL scripts ---
# Each file is mounted individually (sub_path) into the directory upstream's
# docker-compose.yml uses, next to the image's own init-scripts/ and migrations/.
# Mounting the ConfigMap over a whole directory would hide the image's files.

resource "kubernetes_config_map" "db_init_scripts" {
  metadata {
    name      = "db-init-scripts"
    namespace = kubernetes_namespace.supabase.metadata[0].name
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

# --- ConfigMap: Envoy API gateway config ---
# Upstream's Envoy config, unchanged except for the Realtime cluster address:
# compose reaches Realtime by its container name, K8s by the `realtime` Service.
# The listener keeps rewriting the Host header to realtime-dev.supabase-realtime
# because Realtime derives its tenant ID ("realtime-dev") from it.

resource "kubernetes_config_map" "envoy_config" {
  metadata {
    name      = "envoy-config"
    namespace = kubernetes_namespace.supabase.metadata[0].name
  }

  data = {
    "envoy.yaml" = file("${path.module}/docker/volumes/api/envoy/envoy.yaml")
    "cds.yaml" = replace(
      file("${path.module}/docker/volumes/api/envoy/cds.yaml"),
      "address: realtime-dev.supabase-realtime",
      "address: realtime"
    )
    "lds.template.yaml"    = file("${path.module}/docker/volumes/api/envoy/lds.template.yaml")
    "docker-entrypoint.sh" = file("${path.module}/docker/volumes/api/envoy/docker-entrypoint.sh")
  }
}

# --- ConfigMap: Supavisor pooler config ---

resource "kubernetes_config_map" "pooler_config" {
  metadata {
    name      = "pooler-config"
    namespace = kubernetes_namespace.supabase.metadata[0].name
  }

  data = {
    "pooler.exs" = file("${path.module}/docker/volumes/pooler/pooler.exs")
  }
}

# --- ConfigMap: Vector log aggregation config ---
# Upstream's vector.yml reads Docker container logs. On K8s we replace that
# source with kubernetes_logs and rename events to the compose container names,
# so every upstream transform and sink applies unchanged.

locals {
  vector_upstream = yamldecode(file("${path.module}/docker/volumes/logs/vector.yml"))

  vector_config = merge(local.vector_upstream, {
    sources = {
      kubernetes_pods = {
        type                 = "kubernetes_logs"
        extra_field_selector = "metadata.namespace=${local.k8s_namespace}"
      }
    }
    transforms = merge(local.vector_upstream.transforms, {
      # Replaces upstream's docker_logs source of the same name
      docker_host = {
        type   = "remap"
        inputs = ["kubernetes_pods"]
        source = <<-VRL
          container = string!(.kubernetes.container_name)
          if container == "vector" { abort }
          compose_names = {
            "api-gw": "supabase-envoy",
            "realtime": "realtime-dev.supabase-realtime",
            "functions": "supabase-edge-functions"
          }
          mapped = get!(compose_names, [container])
          .container_name = if mapped == null { "supabase-" + container } else { mapped }
          del(.kubernetes)
          del(.file)
        VRL
      }
    })
  })
}

resource "kubernetes_config_map" "vector_config" {
  metadata {
    name      = "vector-config"
    namespace = kubernetes_namespace.supabase.metadata[0].name
  }

  # JSON, not YAML: yamlencode wraps long lines, which would split the
  # ${LOGFLARE_PUBLIC_ACCESS_TOKEN?...} placeholders Vector interpolates in the
  # raw file text.
  data = {
    "vector.json" = jsonencode(local.vector_config)
  }
}

# --- ConfigMap: Edge Functions default files ---
# Copied into the functions PVC by an init container on every start.

resource "kubernetes_config_map" "functions_init" {
  metadata {
    name      = "functions-init"
    namespace = kubernetes_namespace.supabase.metadata[0].name
  }

  data = {
    "main-index.ts"  = file("${path.module}/docker/volumes/functions/main/index.ts")
    "hello-index.ts" = file("${path.module}/docker/volumes/functions/hello/index.ts")
    "deno.jsonc"     = file("${path.module}/docker/volumes/functions/deno.jsonc")
  }
}

# --- Vector RBAC ---
# Vector needs K8s API access to discover pods and read their logs.

resource "kubernetes_service_account" "vector" {
  metadata {
    name      = "vector"
    namespace = kubernetes_namespace.supabase.metadata[0].name
  }
}

resource "kubernetes_cluster_role" "vector" {
  metadata {
    name = "${local.sanitized_name}-vector"
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "namespaces", "nodes"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding" "vector" {
  metadata {
    name = "${local.sanitized_name}-vector"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.vector.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.vector.metadata[0].name
    namespace = kubernetes_namespace.supabase.metadata[0].name
  }
}
