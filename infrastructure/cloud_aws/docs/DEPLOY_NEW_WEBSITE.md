# Deploying a New Static Website

This guide provides step-by-step instructions for deploying a brand-new static website using this Terraform infrastructure.

## Prerequisites

- An AWS account to host the website (the "target account").
- An AWS account to run Terraform from (the "management account"). This can be the same as the target account.
- An IAM user or role in the management account with permissions to assume roles.
- A registered domain name.
- [OpenTofu](https://opentofu.org/) (or Terraform) installed.
- [AWS CLI](https://aws.amazon.com/cli/) installed and configured for your management account.

## Step 1: Set up Prerequisites in Target AWS Account

The first step is to create an IAM role in the target AWS account that Terraform will use to provision resources. A script is provided to automate this.

1.  **Log in to the Target AWS Account**: Ensure your AWS CLI is configured with credentials that have permission to create IAM roles in the target account.

2.  **Run the script**: From the root of the repository, run the `setup-prerequisites.sh` script.

    ```bash
    # Usage: ./infrastructure/cloud_aws/scripts/setup-prerequisites.sh <account_name> <target_account_id> <management_account_id>
    
    # Example:
    ./infrastructure/cloud_aws/scripts/setup-prerequisites.sh myclient 111122223333 999988887777
    ```

    -   `<account_name>`: A friendly name for your project or client (e.g., `myclient`). This will be used to name the IAM role.
    -   `<target_account_id>`: The AWS account ID where the website will be hosted.
    -   `<management_account_id>`: The AWS account ID from which you will run Terraform.

    This script creates an IAM role named `<account_name>-tf-role` with the necessary permissions. It establishes a trust relationship allowing the management account to assume this role.

## Step 2: Grant Permissions in Management Account

In your management AWS account, the IAM user or role that runs Terraform needs permission to assume the role created in Step 1.

Attach the following IAM policy to your Terraform user/role, replacing the placeholders:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "sts:AssumeRole",
            "Resource": "arn:aws:iam::<target_account_id>:role/<account_name>-tf-role"
        }
    ]
}
```

-   `<target_account_id>`: The AWS account ID of the target account.
-   `<account_name>`: The friendly name you used in Step 1.

## Step 3: Set up Terraform Remote State

We use an S3 bucket for remote state storage and a DynamoDB table for state locking.

1.  **Copy the template**:
    ```bash
    # From repository root
    cp -R infrastructure/_templates/static_website_infra_template/remote-state/ infrastructure/accounts/<account_name>/remote-state/
    ```
    Replace `<account_name>` with the same friendly name (e.g., `myclient`).

2.  **Configure variables**:
    Navigate to `infrastructure/accounts/<account_name>/remote-state/`.
    Rename `terraform.tfvars.template` to `terraform.tfvars` and fill in the values:
    -   `aws_region`: The AWS region for your state resources (e.g., `eu-central-1`).
    -   `account_name`: The friendly name (e.g., `myclient`).
    -   `terraform_role_arn`: The ARN of the role created in Step 1 (e.g., `arn:aws:iam::111122223333:role/myclient-tf-role`).
    -   `external_id`: An optional external ID if you configured one on the role.

3.  **Deploy the remote state resources**:
    Run the following commands from `infrastructure/accounts/<account_name>/remote-state/`:
    ```bash
    tofu init
    tofu apply
    ```
    Take note of the `state_bucket` and `dynamodb_table` outputs. You'll need them next.

## Step 4: Configure Website Infrastructure

Now, configure the actual website resources.

1.  **Copy the template**:
    ```bash
    # From repository root
    mkdir -p infrastructure/accounts/<account_name>/
    cp infrastructure/_templates/static_website_infra_template/{main.tf,variables.tf,outputs.tf,backend.tf} infrastructure/accounts/<account_name>/
    cp infrastructure/_templates/static_website_infra_template/terraform.tfvars.template infrastructure/accounts/<account_name>/terraform.tfvars
    cp infrastructure/_templates/static_website_infra_template/backend.hcl infrastructure/accounts/<account_name>/
    ```

2.  **Configure the backend**:
    Edit `infrastructure/accounts/<account_name>/backend.hcl`. Use the outputs from Step 3 and your account details.
    ```hcl
    bucket          = "myclient-tf-state" // Output from Step 3
    key             = "myclient/my-website.tfstate" // Unique key for this deployment
    region          = "eu-central-1"
    dynamodb_table  = "myclient-tf-locks" // Output from Step 3
    assume_role = {
        role_arn    = "arn:aws:iam::111122223333:role/myclient-tf-role"
        external_id = "" // Optional
    }
    ```

3.  **Configure your website**:
    Edit `infrastructure/accounts/<account_name>/terraform.tfvars`. Define your domain(s) and stage(s).
    See `infrastructure/_templates/static_website_infra_template/terraform.tfvars.template` for a detailed example. A minimal configuration looks like this:
    ```hcl
    account_name = "myclient"

    aws_account = {
      account_id = "111122223333"
      role_arn   = "arn:aws:iam::111122223333:role/myclient-tf-role"
      region     = "eu-central-1"
      external_id = ""
    }

    websites = {
      "example.com" = {
        domain_name = "example.com"
        stages = [
          {
            name                    = "production"
            subdomain               = "www"
            content_path            = "websites/example.com/www" // Relative to repo root
            www_redirect            = true
            maintenance_mode        = false
            maintenance_allowed_ips = []
          }
        ]
      }
    }
    ```

4.  **Add website content**:
    Create the directory specified in `content_path` (e.g., `websites/example.com/www/`) and place at least an `index.html` file inside it.

## Step 5: Deploy the Website

You are now ready to deploy.

1.  **Initialize Terraform**:
    Navigate to your account directory (`infrastructure/accounts/<account_name>/`) and run init:
    ```bash
    cd infrastructure/accounts/myclient/
    tofu init -backend-config=backend.hcl
    ```

2.  **Deploy**:
    You can deploy all websites in the account or a specific stage of a website using the `deploy.sh` script.

    ```bash
    # To deploy everything for the 'myclient' account
    ../../cloud_aws/scripts/deploy.sh account myclient

    # To deploy only the 'www' stage of 'example.com'
    ../../cloud_aws/scripts/deploy.sh stage example.com www
    ```
    The script will show you a plan and then apply it.

## Step 6: Final DNS Configuration

After the first deployment, you need to perform two manual DNS steps at your domain registrar.

1.  **ACM Certificate Validation**: Terraform's output will include DNS records (CNAMEs) required to validate your SSL certificate. Add these records to your domain's DNS settings. This is a one-time setup per domain.

2.  **Update Name Servers (NS)**: The Terraform deployment creates a Route 53 Hosted Zone for your domain. The output will show the AWS Name Servers for this zone. Update the NS records at your domain registrar to point to these AWS Name Servers. This delegates DNS control for your domain to AWS.

After DNS propagates (which can take up to 48 hours), your website will be live.
