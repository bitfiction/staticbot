# modules/backend/main.tf
# Placeholder for future backend services
# Example structure for API Gateway + Lambda + RDS

# variable "enable_api" {
#   type    = bool
#   default = false
# }

# variable "enable_database" {
#   type    = bool
#   default = false
# }

# API Gateway placeholder
# resource "aws_api_gateway_rest_api" "api" {
#   count = var.enable_api ? 1 : 0
#   name  = "static-site-api"
# }

# Lambda function placeholder
# resource "aws_lambda_function" "api" {
#   count = var.enable_api ? 1 : 0
# }

# RDS instance placeholder
# resource "aws_db_instance" "database" {
#   count = var.enable_database ? 1 : 0
# }