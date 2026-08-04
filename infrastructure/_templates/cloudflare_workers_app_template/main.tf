terraform {
  required_version = ">= 1.0.0"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_account.api_token
}

locals {
  account_id = var.cloudflare_account.account_id
}

# Routes table entry: when a request reaches the dispatch Worker with
# Host = var.app.customer_hostname, the dispatch Worker looks up this entry
# and forwards to env.DISPATCH.get(<value>).fetch(request).
#
# Hostname is lowercased here to match the dispatch Worker's KV lookup
# (which also lowercases the incoming Host).
resource "cloudflare_workers_kv" "route_entry" {
  account_id   = local.account_id
  namespace_id = var.shared_infra.routes_kv_namespace_id
  key_name     = lower(var.app.customer_hostname)
  value        = var.app.worker_name
}

# Custom Hostname: enrolls var.app.customer_hostname in the SaaS zone so CF
# can issue a TLS cert for it via SSL-for-SaaS. The customer points DNS at
# var.shared_infra.fallback_hostname (ALIAS or CNAME); CF terminates TLS and
# routes the decrypted request through the dispatch Worker.
#
# Note: the WfP user-Worker bundle itself is NOT declared here. Per CF provider
# v5, individual WfP scripts are not a TF resource type -- wrangler creates and
# updates the bundle via `wrangler deploy --dispatch-namespace`. The wrangler
# step also pushes plain_env (as [vars] in wrangler.toml) and secrets (via
# `wrangler secret put`), so those stay out of TF state entirely.
resource "cloudflare_custom_hostname" "customer" {
  zone_id  = var.shared_infra.zone_id
  hostname = var.app.customer_hostname

  ssl = {
    method                = "txt"
    type                  = "dv"
    bundle_method         = "ubiquitous"
    wildcard              = false
    settings = {
      min_tls_version = "1.2"
    }
  }
}
