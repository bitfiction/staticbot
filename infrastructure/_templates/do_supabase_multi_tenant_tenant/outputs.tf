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
