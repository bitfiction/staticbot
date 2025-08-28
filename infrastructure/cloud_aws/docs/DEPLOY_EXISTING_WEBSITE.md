# Migrating an Existing Staticbot Website

This guide is for users who have an existing website previously deployed with the "Staticbot system" and have access to its Terraform state file and configuration.

## Prerequisites

- An existing Terraform state file (`.tfstate`).
- The Terraform configuration files (`.tf`, `.tfvars`) for the existing deployment.
- Access to the AWS account where the website is hosted.
- [OpenTofu](https://opentofu.org/) (or Terraform) installed.
- [AWS CLI](https://aws.amazon.com/cli/) installed.

## Goal

The goal is to migrate your existing infrastructure's state into the remote backend managed by this repository's structure and update your configuration to use the shared modules.

## Step 1: Set Up the Repository Structure

1.  **Clone this repository**:
    ```bash
    git clone <your-repo-url>
    cd <repo-name>
    ```

2.  **Create account directory**:
    Create a new directory for your deployment under `infrastructure/accounts/`. Use a friendly name for the account (e.g., `myclient`).
    ```bash
    mkdir -p infrastructure/accounts/myclient
    ```

3.  **Copy existing configuration**:
    Copy your existing `.tf` files, `terraform.tfvars`, and any other relevant files into `infrastructure/accounts/myclient/`.

4.  **Organize website content**:
    Move your website's static files into the `websites/` directory, following the structure `websites/<domain_name>/<subdomain>/`.

## Step 2: Set up the Remote Backend

If your existing deployment doesn't already use an S3 remote backend, you need to create one.

1.  **Follow Step 1-3 from the [new website deployment guide](./DEPLOY_NEW_WEBSITE.md)** to:
    -   Create the cross-account IAM role (`<account_name>-tf-role`).
    -   Set up permissions for your management user/role.
    -   Create the S3 bucket and DynamoDB table for the remote state.

2.  **Configure `backend.hcl`**:
    Create a `backend.hcl` file in `infrastructure/accounts/myclient/` with the details of your remote backend.
    ```hcl
    bucket          = "myclient-tf-state"
    key             = "myclient/my-website.tfstate"
    region          = "eu-central-1"
    dynamodb_table  = "myclient-tf-locks"
    assume_role = {
        role_arn    = "arn:aws:iam::111122223333:role/myclient-tf-role"
    }
    ```

## Step 3: Adapt Configuration to Use Modules

Your existing Terraform code needs to be adapted to use the structure of this repository.

1.  **Replace resources with module calls**:
    Your main Terraform file (e.g., `main.tf`) in `infrastructure/accounts/myclient/` should be simplified to call the root module, similar to the template at `infrastructure/_templates/static_website_infra_template/main.tf`.

    Remove the individual resource definitions (`aws_s3_bucket`, `aws_cloudfront_distribution`, etc.) from your configuration, as these are now handled by the `static-website` module.

2.  **Update `terraform.tfvars`**:
    Ensure your `terraform.tfvars` file matches the structure required by the root module (see `infrastructure/_templates/static_website_infra_template/variables.tf`). You will define your AWS account details and websites configuration here.

## Step 4: Initialize and Migrate State

1.  **Initialize Terraform**:
    Navigate to `infrastructure/accounts/myclient/` and run `init`. If you have a local state file, Terraform will detect it and the new backend configuration.
    ```bash
    cd infrastructure/accounts/myclient
    tofu init -backend-config=backend.hcl
    ```
    It will prompt you to copy the existing state to the new backend. Confirm by typing `yes`.

2.  **Review the Plan**:
    After initialization, run a plan to see what changes Terraform wants to make.
    ```bash
    tofu plan
    ```
    Ideally, if you have correctly mapped your old resources to the new module structure and variables, the plan should show minimal or no changes (e.g., only tag updates). If it plans to destroy and recreate major resources like a CloudFront distribution or S3 bucket, **do not proceed**. Revisit your configuration to ensure it matches the existing infrastructure.

## Step 5: Apply Changes

Once you are confident that the plan is safe and reflects only the intended changes, apply it.
```bash
tofu apply
```

Your website is now managed by the new infrastructure structure. Future deployments can be done using the `deploy.sh` script as described in the main README.
