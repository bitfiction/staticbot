output "cluster_endpoint" {
  description = "DOKS cluster API endpoint"
  value       = digitalocean_kubernetes_cluster.main.endpoint
}

output "kong_url" {
  description = "URL for Kong (Supabase API Gateway)"
  value       = "https://${var.domain_name}"
}

output "studio_url" {
  description = "URL for Supabase Studio"
  value       = "https://${var.domain_name}"
}

output "load_balancer_ip" {
  description = "IP of the DO Load Balancer (point DNS here)"
  value       = data.kubernetes_service.ingress_nginx_controller.status[0].load_balancer[0].ingress[0].ip
}
