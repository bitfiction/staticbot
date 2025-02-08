# Cross-Account IAM Role Deployment Guide

This guide explains how to deploy an IAM role that enables cross-account access with S3 permissions. The role can be deployed either manually through CloudFormation or automatically using Terraform.

## Role Details

The deployment creates an IAM role with the following specifications:
- Role Name: `staticbot-crossaccount-operator`
- Trusted Entity: Another AWS account's role (specified by account ID)
- Permissions: S3 read-only access plus custom S3 permissions for specific operations

## Manual Deployment (CloudFormation)

### Prerequisites
- AWS Console access with permissions to create IAM roles
- The AWS account ID that will be trusted to assume this role

### Deployment Steps

1. Navigate to the CloudFormation console in your AWS account:
   ```
   https://console.aws.amazon.com/cloudformation
   ```

2. Click "Create stack" and choose "With new resources (standard)"

3. In the "Specify template" section:
   - Select "Upload a template file"
   - Upload the provided YAML template file

4. Click "Next" and provide the following parameters:
   - Stack name: Choose a meaningful name (e.g., `staticbot-cross-account-role`)
   - TrustedAccountId: Enter the AWS account ID that should be trusted

5. Click through the next screens, reviewing the default options

6. On the final review page:
   - Check the acknowledgment for IAM resource creation
   - Click "Create stack"

7. Wait for the stack creation to complete (usually takes 2-3 minutes)

8. Once complete, find the role ARN in the stack's Outputs tab

## Automated Deployment (Terraform)

### Prerequisites
- Terraform installed (version 0.12 or later)
- AWS credentials configured
- Basic understanding of Terraform

### Terraform Configuration

Create a new file named `main.tf` with the following content:

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"  # Change to your desired region
}

variable "trusted_account_id" {
  description = "AWS Account ID that will be trusted to assume this role"
  type        = string
  default     = "682033486080"
}

resource "aws_iam_role" "cross_account_role" {
  name        = "staticbot-crossaccount-operator"
  description = "Role for StaticBot cross-account access"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = ["arn:aws:iam::${var.trusted_account_id}:role/staticbot-crossaccount-operator-*"]
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  managed_policy_arns = ["arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"]
}

resource "aws_iam_role_policy" "s3_custom_access" {
  name = "S3CustomAccess"
  role = aws_iam_role.cross_account_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::*",
          "arn:aws:s3:::*/*"
        ]
      }
    ]
  })
}

output "role_arn" {
  description = "ARN of the created IAM role"
  value       = aws_iam_role.cross_account_role.arn
}
```

### Deployment Steps

1. Initialize Terraform:
   ```bash
   terraform init
   ```

2. Review the planned changes:
   ```bash
   terraform plan
   ```

3. Apply the configuration:
   ```bash
   terraform apply
   ```

4. Confirm the changes by typing `yes` when prompted

5. Note the role ARN from the outputs

## Verification

After deployment (using either method), verify the role:

1. Navigate to the IAM console
2. Find the role named `staticbot-crossaccount-operator`
3. Verify the trust relationship includes the specified account ID
4. Confirm the attached policies:
   - AmazonS3ReadOnlyAccess managed policy
   - S3CustomAccess inline policy

## Security Considerations

- The role provides broad S3 access. Consider limiting the S3 bucket resources if possible
- Review the trust relationship regularly to ensure it remains appropriate
- Monitor role usage through AWS CloudTrail
- Consider implementing additional conditions in the trust relationship (e.g., MFA, source IP)

## Troubleshooting

Common issues and solutions:

1. Permission Denied
   - Verify your AWS credentials have sufficient permissions to create IAM roles
   - Check if similar role name already exists

2. Trust Relationship Issues
   - Confirm the trusted account ID is correct
   - Verify the role name pattern in the trusted account matches

3. S3 Access Issues
   - Verify the role has both the managed policy and custom policy attached
   - Check if S3 bucket policies aren't restricting access

For additional help, consult AWS documentation or contact AWS Support.