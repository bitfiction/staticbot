output "worker_name" {
  description = "WfP user-Worker script name. Wrangler uses this for `wrangler deploy --name <worker_name>`."
  # Echoed from input -- the script itself isn't a TF resource (wrangler owns it).
  value = var.app.worker_name
}

output "dispatch_namespace_name" {
  description = "Echo of the dispatch namespace from shared infra. Convenience for downstream wrangler step."
  value       = var.shared_infra.dispatch_namespace_name
}

output "customer_hostname" {
  description = "The hostname the customer brought. Used in DNS instructions + smoke check."
  value       = var.app.customer_hostname
}

output "worker_url" {
  description = "Public URL where the deployed app will be served once DNS resolves and the cert is active."
  value       = "https://${var.app.customer_hostname}"
}

output "apex_alias_target" {
  description = "What the customer puts in their ALIAS / CNAME record. Shown verbatim in deployment DNS instructions."
  value       = var.shared_infra.fallback_hostname
}

output "ownership_verification" {
  description = "CF-provided ownership-verification record (when present). The deployment UI surfaces this alongside DCV."
  value       = try(cloudflare_custom_hostname.customer.ownership_verification, null)
}

output "custom_hostname_id" {
  description = "CF Custom Hostname ID. Java uses this to poll cert status + fetch DCV records via the CF API (the v5 TF resource doesn't expose DCV records directly -- they arrive asynchronously)."
  value       = cloudflare_custom_hostname.customer.id
}

output "custom_hostname_status" {
  description = "Cert status snapshot at apply time: pending | active | failed | pending_validation | pending_issuance | pending_deployment | pending_deletion | deleted. The UI polls the CF API in real time for live updates."
  value       = cloudflare_custom_hostname.customer.status
}

output "kv_route_entry_id" {
  description = "ID of the STATICBOT_ROUTES KV entry. Useful for state inspection and Phase 2 escape-hatch migration."
  value       = cloudflare_workers_kv.route_entry.id
}
