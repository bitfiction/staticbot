# infrastructure/providers.tf

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    # Will be configured via -backend-config options during init
  }
}

# Default provider configuration for the accounts's region
provider "aws" {
  region = var.aws_account.region

  assume_role {
    role_arn = var.aws_account.role_arn
  }

  default_tags {
    tags = merge(var.common_tags, {
      Account = var.account_name
    })
  }
}

# Provider for ACM certificates (must be in us-east-1 for CloudFront)
provider "aws" {
  alias  = "certificates"
  region = "us-east-1"

  assume_role {
    role_arn = var.aws_account.role_arn
  }

  default_tags {
    tags = merge(var.common_tags, {
      Account = var.account_name
    })
  }
}
