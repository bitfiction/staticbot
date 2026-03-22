output "alb_dns_name" {
  description = "DNS name of the Load Balancer"
  value       = aws_lb.main.dns_name
}

output "kong_url" {
  description = "URL for Kong (Supabase API Gateway)"
  value       = "http://${aws_lb.main.dns_name}:8000"
}

output "studio_url" {
  description = "URL for Supabase Studio"
  value       = "http://${aws_lb.main.dns_name}/studio" 
  # Note: Studio routing in ALB might need adjustment (port 3000 vs /studio path)
  # In network.tf I added a listener rule for /studio* -> studio:3000
}
