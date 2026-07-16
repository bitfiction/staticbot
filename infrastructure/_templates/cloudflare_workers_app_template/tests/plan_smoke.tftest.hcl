# Plan-mode smoke test: with a mocked Cloudflare provider, run a tofu plan and
# assert the output shape downstream jobs / the UI depend on. No real CF API
# calls -- the resources are created in the plan but never sent over the wire.
#
# Run:
#   tofu init -backend=false
#   tofu test

mock_provider "cloudflare" {}

variables {
  account_name = "staticbot-acme-prod"

  cloudflare_account = {
    account_id = "cf-acc-yyy"
    api_token  = "cf-token-xxx"
  }

  shared_infra = {
    dispatch_namespace_name = "staticbot-apps-prod"
    dispatch_namespace_id   = "ns-id-123"
    routes_kv_namespace_id  = "kv-id-456"
    zone_id                 = "zone-id-789"
    fallback_hostname       = "apps.staticbot.app"
  }

  app = {
    worker_name       = "acme-app"
    customer_hostname = "app.acme.com"
    plain_env = {
      VITE_SUPABASE_URL = "https://abc.supabase.co"
    }
  }

  worker_secrets = {
    DB_PASSWORD = "shouldnotleak"
  }
}

run "outputs_have_expected_shape" {
  command = plan

  assert {
    condition     = output.worker_name == "acme-app"
    error_message = "worker_name output should echo the configured app.worker_name"
  }

  assert {
    condition     = output.customer_hostname == "app.acme.com"
    error_message = "customer_hostname output should echo the configured customer hostname"
  }

  assert {
    condition     = output.worker_url == "https://app.acme.com"
    error_message = "worker_url output must be https://<customer_hostname> -- the UI uses this verbatim"
  }

  assert {
    condition     = output.apex_alias_target == "apps.staticbot.app"
    error_message = "apex_alias_target must echo shared_infra.fallback_hostname -- this is what customers ALIAS to"
  }

  assert {
    condition     = output.dispatch_namespace_name == "staticbot-apps-prod"
    error_message = "dispatch_namespace_name output is what the wrangler_deploy job uses for --dispatch-namespace"
  }
}

run "kv_route_entry_is_lowercased" {
  command = plan

  variables {
    app = {
      worker_name       = "acme-app"
      customer_hostname = "App.Acme.COM" # mixed case to verify lowercase() is applied
      plain_env         = {}
    }
  }

  assert {
    condition     = cloudflare_workers_kv.route_entry.key_name == "app.acme.com"
    error_message = "STATICBOT_ROUTES key must be lowercased -- dispatch Worker only looks up lowercase hostnames"
  }
}

run "kv_route_entry_value_is_worker_name" {
  command = plan

  assert {
    condition     = cloudflare_workers_kv.route_entry.value == "acme-app"
    error_message = "STATICBOT_ROUTES value must be the WfP user-Worker name -- dispatch reads this and calls env.DISPATCH.get(value)"
  }
}

run "custom_hostname_uses_customer_hostname" {
  command = plan

  assert {
    condition     = cloudflare_custom_hostname.customer.hostname == "app.acme.com"
    error_message = "cloudflare_custom_hostname.hostname must match var.app.customer_hostname"
  }

  assert {
    condition     = cloudflare_custom_hostname.customer.zone_id == "zone-id-789"
    error_message = "Custom Hostname must be created in the SaaS zone (shared_infra.zone_id)"
  }
}

run "ssl_method_is_txt_dv_for_saas_pattern" {
  command = plan

  # SSL for SaaS with DCV-via-TXT is the recommended path when the customer's
  # DNS stays at their registrar. Locking these in to catch accidental changes
  # that would break the per-customer DNS instruction flow.
  assert {
    condition     = cloudflare_custom_hostname.customer.ssl.method == "txt"
    error_message = "ssl.method must be 'txt' so customers can validate without moving DNS to our zone"
  }

  assert {
    condition     = cloudflare_custom_hostname.customer.ssl.type == "dv"
    error_message = "ssl.type must be 'dv' -- 'ev' / custom certs are Enterprise-only and not in Phase 1 scope"
  }
}
