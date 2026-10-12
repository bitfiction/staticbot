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

output "backup_bucket" {
  description = "S3 bucket holding the WAL-G backups"
  value       = aws_s3_bucket.pg_backups.bucket
}

output "ecs_cluster" {
  description = "ECS cluster (for the restore runbook)"
  value       = aws_ecs_cluster.main.name
}

output "db_restore_task_definition" {
  description = "Task definition family to run for a point-in-time restore"
  value       = aws_ecs_task_definition.db_restore.family
}

output "private_subnet_ids" {
  description = "Subnets for `aws ecs run-task` (restore runbook)"
  value       = aws_subnet.private[*].id
}

output "ecs_tasks_security_group_id" {
  description = "Security group for `aws ecs run-task` (restore runbook)"
  value       = aws_security_group.ecs_tasks.id
}

output "log_group_name" {
  description = "CloudWatch log group of all tasks (restore runbook)"
  value       = aws_cloudwatch_log_group.main.name
}
