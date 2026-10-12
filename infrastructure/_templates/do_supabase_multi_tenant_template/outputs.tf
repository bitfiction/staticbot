output "tenant_id" {
  description = "Tenant identifier"
  value       = var.tenant_id
}

output "tenant_namespace" {
  description = "Kubernetes namespace for this tenant"
  value       = kubernetes_namespace.tenant.metadata[0].name
}

output "api_url" {
  description = "Public API URL for this tenant (e.g. https://{tenant-id}.sb.frever.net)"
  value       = local.api_url
}

output "anon_key" {
  description = "Anon key for client-side use"
  value       = var.anon_key
  sensitive   = true
}

output "service_role_key" {
  description = "Service role key for server-side use"
  value       = var.service_role_key
  sensitive   = true
}

output "db_host" {
  description = "In-cluster hostname of the tenant's Postgres"
  value       = local.db_fqdn
}

output "pooler_host" {
  description = "In-cluster hostname of the shared Supavisor pooler (session mode on 5432, transaction mode on 6543)"
  value       = local.supavisor_host
}

output "pooler_user" {
  description = "Database user for connecting through Supavisor; Supavisor routes it to this tenant's Postgres"
  value       = "postgres.${var.tenant_id}"
}
