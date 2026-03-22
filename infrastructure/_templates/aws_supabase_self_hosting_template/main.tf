terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  assume_role {
    role_arn    = var.terraform_role_arn
    external_id = var.external_id
  }

  default_tags {
    tags = {
      Project   = var.project_name
      Terraform = "true"
    }
  }
}

locals {
  # Truncated names for resources with strict AWS length limits
  # ALB target groups: max 32 chars, IAM roles/policies: max 64 chars
  short_name = substr(var.project_name, 0, 22)
  iam_name   = substr(var.project_name, 0, 48)
}
