# Multi-Account Static Website Infrastructure

This repository contains infrastructure as code for managing multiple static websites across different AWS accounts, with support for multiple deployment stages (e.g., dev, www) per website.

## Features

-   Multi-account AWS infrastructure management
-   Multiple websites per AWS account support
-   Stage-based deployments
-   Automatic SSL certificate management with AWS Certificate Manager
-   CloudFront CDN for performance and security
-   Custom error pages and maintenance mode
-   Intelligent redirects (e.g., WWW/non-WWW handling)

## Prerequisites

-   AWS CLI configured with appropriate credentials
-   OpenTofu (or Terraform) installed (version >=1.0.0)
-   A Bash shell for running scripts

## Repository Structure

-   `infrastructure/accounts/`: Contains the Terraform configurations for each client/account.
-   `infrastructure/cloud_aws/modules/`: Reusable Terraform modules (e.g., `static-website`).
-   `infrastructure/cloud_aws/scripts/`: Helper scripts for deployment and setup.
-   `infrastructure/_templates/`: Template files for bootstrapping new accounts.
-   `websites/`: Contains the actual static content for the websites.

## Deployment Guides

This repository supports two main workflows: deploying a brand-new website, or migrating a website previously managed by an older system.

-   **[Guide: Deploying a New Website](./docs/DEPLOY_NEW_WEBSITE.md)**
    
    Follow this guide for a complete walkthrough of setting up a new website from scratch. This includes setting up AWS prerequisites, configuring remote state, and deploying the infrastructure for the first time.

-   **[Guide: Migrating an Existing Website](./docs/DEPLOY_EXISTING_WEBSITE.md)**
    
    Follow this guide if you have an existing website with a Terraform state file that you want to migrate into this management structure.

## Deployment Process Overview

Once initial setup is complete, deploying changes is done via the `deploy.sh` script.

1.  **Navigate to the account directory**:
    ```bash
    cd infrastructure/accounts/<account_name>/
    ```

2.  **Run the deploy script**:
    The script allows you to deploy all changes for an account or target a specific website stage.

    ```bash
    # Deploy all changes in the current configuration (for the specified account)
    ../../cloud_aws/scripts/deploy.sh account <account_name>

    # Deploy only the 'www' stage of 'example.com'
    ../../cloud_aws/scripts/deploy.sh stage example.com www
    ```

## Maintenance Mode

To enable maintenance mode for a specific website stage:

1.  In `infrastructure/accounts/<account_name>/terraform.tfvars`, find the stage definition and update it:
    ```hcl
    # ... inside a stage block ...
    maintenance_mode        = true
    maintenance_allowed_ips = ["YOUR_IP_ADDRESS/32"] // Optional: Add IPs that can bypass maintenance
    ```

2.  Apply the changes for that specific stage:
    ```bash
    # From infrastructure/accounts/<account_name>/
    ../../cloud_aws/scripts/deploy.sh stage example.com www
    ```

## Security Considerations

-   All S3 buckets are private and accessed only through CloudFront OAI.
-   SSL/TLS is enforced via CloudFront.
-   Public access to buckets is blocked by default.
-   Infrastructure changes are tracked in a remote state backend with state locking.
