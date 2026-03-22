resource "aws_cloudwatch_log_group" "main" {
  name              = "/ecs/${local.sanitized_name}"
  retention_in_days = 30
}
