terraform {
  backend "s3" {
    # Do NOT set these values here. They will be passed via -backend-config:
    # bucket         = "staticbot-prod-terraform-state"
    # key            = "cloudflare-tenants/<account_name>.tfstate"
    # region         = "eu-central-1"
    # dynamodb_table = "staticbot-prod-terraform-locks"
    # role_arn       = "arn:aws:iam::108302757870:role/staticbot-prod-terraform-role"
    encrypt = true
  }
}
