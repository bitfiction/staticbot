terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  # region is supplied via AWS_REGION env var (set by the worker).
  # No assume_role — Cloudflare Workers deployments use the worker's own
  # AWS credentials for state-bucket access. All tenants share
  # staticbot-prod-terraform-state, unlike per-customer AWS deployments.
}
