# infrastructure/providers.tf

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  
  backend "s3" {
    # Will be configured via backend-config files
  }
}

# Create provider configurations for each AWS account
locals {
  # Get unique list of accounts being used
  used_accounts = distinct([
    for website in var.websites : website.aws_account
  ])
}

# Default provider configuration
provider "aws" {
  region = var.aws_region
  
  assume_role {
    role_arn = var.aws_account.role_arn
  }

  default_tags {
    tags = var.common_tags
  }
}

# Generate provider configurations for each account
provider "aws" {
  alias  = "account1"
  region = var.aws_accounts["account1"].region
  assume_role {
    role_arn = var.aws_accounts["account1"].role_arn
  }
}

provider "aws" {
  alias  = "account2"
  region = var.aws_accounts["account2"].region
  assume_role {
    role_arn = var.aws_accounts["account2"].role_arn
  }
}

provider "aws" {
  alias  = "account3"
  region = var.aws_accounts["account3"].region
  assume_role {
    role_arn = var.aws_accounts["account3"].role_arn
  }
}

# Certificate providers (required in us-east-1 for CloudFront)
provider "aws" {
  alias  = "account1_certificates"
  region = "us-east-1"
  assume_role {
    role_arn = var.aws_accounts["account1"].role_arn
  }
}

provider "aws" {
  alias  = "account2_certificates"
  region = "us-east-1"
  assume_role {
    role_arn = var.aws_accounts["account2"].role_arn
  }
}

provider "aws" {
  alias  = "account3_certificates"
  region = "us-east-1"
  assume_role {
    role_arn = var.aws_accounts["account3"].role_arn
  }
}