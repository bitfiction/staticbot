output "alb_dns_name" {
  description = "DNS name of the Load Balancer"
  value       = aws_lb.main.dns_name
}

output "api_url" {
  description = "Supabase API URL (API gateway)"
  value       = "http://${aws_lb.main.dns_name}"
}

output "studio_url" {
  description = "Supabase Studio (served by the API gateway behind basic auth)"
  value       = "http://${aws_lb.main.dns_name}"
}
