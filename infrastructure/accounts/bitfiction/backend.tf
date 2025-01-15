# infrastructure/accounts/bitfiction/backend.tf

terraform {
  backend "s3" {
    # Do NOT set these values here. They will be passed via -backend-config
    # bucket         = "prod-terraform-state"
    # key            = "terraform.tfstate"
    # region         = "us-east-1"
    # dynamodb_table = "prod-terraform-locks"
    # role_arn       = "arn:aws:iam::111111111111:role/prod-terraform-role"
    encrypt        = true
  }
}