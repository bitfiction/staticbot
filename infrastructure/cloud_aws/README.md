# Multi-Account Static Website Infrastructure

This repository contains infrastructure as code for managing multiple static websites across different AWS accounts, with support for multiple deployment stages (dev, preview, www) per website.

## Initiate directory structure

mkdir -p scripts infrastructure/{accounts/{example,another-example},modules/{static-website,backend},remote-state} websites/{example.com,example.org,another-example.com}/{dev,preview,www} tests/infrastructure

## Features

- Multi-account AWS infrastructure management
- Multiple websites per AWS account support
- Stage-based deployments (dev, preview, www)
- Automatic SSL certificate management
- CloudFront CDN integration
- Custom error pages
- Intelligent redirects:
  - Language/region-based
  - WWW/non-WWW handling
  - Maintenance mode support
- Infrastructure testing
- Drift detection

## Prerequisites

- AWS CLI configured with appropriate credentials
- OpenTofu/Terraform installed (version >=1.0.0)
- Go installed (for running tests)
- Bash shell (for running scripts)

## Initial Setup

1. Clone the repository:
```bash
git clone <your-repo-url>
cd <repo-name>
```

2. Set up AWS accounts prerequisites:
   For each AWS account where you want to deploy websites, you need to set up an IAM role that Terraform will assume.
   The `setup-prerequisites.sh` script automates the creation of this role (`<account_name>-tf-role`) and a policy with necessary permissions.

   ```bash
   # Make the script executable (run from repository root)
   chmod +x infrastructure/cloud_aws/scripts/setup-prerequisites.sh

   # Run for each AWS account, providing an <account_name> (e.g., "myclient") and the AWS Account ID
   ./infrastructure/cloud_aws/scripts/setup-prerequisites.sh <account_name> <aws-account-id>
   # Example: ./infrastructure/cloud_aws/scripts/setup-prerequisites.sh myclient 111122223333
   ```
   This will create a role named `<account_name>-tf-role` in the target account.

3. Configure IAM User/Role to Assume the Terraform Role:
   The IAM principal (user or role) that will execute Terraform (likely in your management or CI/CD account) needs permission to assume the `<account_name>-tf-role` created in the previous step.
   Attach a policy to your calling IAM user/role similar to this:
   ```json
   {
       "Version": "2012-10-17",
       "Statement": [
           {
               "Sid": "AllowAssumeTerraformRole",
               "Effect": "Allow",
               "Action": "sts:AssumeRole",
               "Resource": "arn:aws:iam::<aws-account-id>:role/<account_name>-tf-role"
           }
       ]
   }
   ```
   Replace `<aws-account-id>` with the target account ID and `<account_name>-tf-role` with the specific role name.

4. Configure AWS CLI Profile:
   Add a profile to your `~/.aws/config` file to use the assumed role. This profile will be used by Terraform.
   ```ini
   [profile <account_name>-terraform-role]
   role_arn = arn:aws:iam::<aws-account-id>:role/<account_name>-tf-role
   source_profile = <your_iam_user_profile_that_can_assume_the_role>
   # external_id = <if_you_configured_one_manually_after_script_execution>
   ```
   Replace placeholders accordingly. `<source_profile>` is the profile associated with the IAM user that has permission to assume the role.

5. Set up Remote State Backend:
   For each account, you need to configure a remote state backend (S3 bucket and DynamoDB table for locking).
   a. Copy the remote state template:
      ```bash
      # From repository root
      cp -R infrastructure/_templates/static_website_infra_template/remote-state/ infrastructure/accounts/<account_name>/remote-state/
      ```
   b. Navigate to the new directory:
      ```bash
      cd infrastructure/accounts/<account_name>/remote-state/
      ```
   c. Create `terraform.tfvars` from `terraform.tfvars.template` in this directory and fill in the values:
      - `aws_region`: e.g., "eu-central-1"
      - `account_name`: The same `<account_name>` used before.
      - `terraform_role_arn`: The ARN of the `<account_name>-tf-role` (e.g., `arn:aws:iam::<aws-account-id>:role/<account_name>-tf-role`).
      - `external_id`: An external ID if you have configured one for the role assumption.
   d. Initialize and apply to create the S3 bucket and DynamoDB table:
      ```bash
      # Ensure your AWS_PROFILE is set to use the role that can manage these resources,
      # or that your source_profile has these permissions directly for the initial setup.
      # The provider in this module uses the terraform_role_arn for its operations.
      export AWS_PROFILE=<profile_that_can_assume_terraform_role_or_has_direct_permissions>
      tofu init
      tofu apply
      ```
      Note the outputs, as they will be used in `backend.hcl` for website deployments.

6. Configure Website Infrastructure:
   a. Create an account-specific directory for your website infrastructure if it doesn't exist:
      ```bash
      # From repository root
      mkdir -p infrastructure/accounts/<account_name>/
      ```
   b. Copy the main infrastructure template files:
      ```bash
      # From repository root
      cp infrastructure/_templates/static_website_infra_template/{main.tf,variables.tf,outputs.tf,terraform.tfvars.template,backend.tf,backend.hcl} infrastructure/accounts/<account_name>/
      mv infrastructure/accounts/<account_name>/terraform.tfvars.template infrastructure/accounts/<account_name>/terraform.tfvars
      ```
   c. Edit `infrastructure/accounts/<account_name>/terraform.tfvars` and configure your websites.
      Refer to `infrastructure/_templates/static_website_infra_template/terraform.tfvars.template` for the structure.
      Example:
      ```hcl
      account_name = "<account_name>" // e.g., "myclient"

      aws_account = {
        account_id = "<target_account_id>"       // e.g., "111122223333"
        role_arn   = "arn:aws:iam::<target_account_id>:role/<account_name>-tf-role"
        region     = "<target_region>"           // e.g., "eu-central-1"
        external_id = "<external_id_if_any>"   // Optional: if your role requires it
      }

      websites = {
        "example.com" = {
          domain_name = "example.com" // This should match the key
          stages = [
            {
              name                    = "dev"
              subdomain               = "dev"
              content_path            = "websites/example.com/dev" // Relative to repo root
              www_redirect            = false
              maintenance_mode        = false
              maintenance_allowed_ips = []
            },
            {
              name                    = "www" // Or "production", "live" etc.
              subdomain               = "www"
              content_path            = "websites/example.com/www" // Relative to repo root
              www_redirect            = true  // Redirect example.com to www.example.com
              maintenance_mode        = false
              maintenance_allowed_ips = []
            }
          ]
        },
        "another-site.org" = {
          domain_name = "another-site.org"
          stages = [
            {
              name                    = "www"
              subdomain               = "www"
              content_path            = "websites/another-site.org/www"
              www_redirect            = false // No redirect, www.another-site.org is canonical
              maintenance_mode        = false
              maintenance_allowed_ips = []
            }
          ]
        }
      }

      common_tags = {
        Domain     = "Multiple" // Or specific if only one domain in this tfvars
        DeployedBy = "Staticbot"
        ManagedBy  = "Terraform"
      }
      ```
      Ensure `content_path` points to the correct directory within your `websites/` folder (relative from the repository root). The Terraform module will expect an `index.html` in this path.

## Deployment

1. Configure `backend.hcl`:
   In your `infrastructure/accounts/<account_name>/` directory, edit the `backend.hcl` file.
   Fill in the details using the outputs from the remote state setup (Step 5d above) and your AWS account details.
   Example `backend.hcl` (copied from `infrastructure/_templates/static_website_infra_template/backend.hcl`):
   ```hcl
   bucket          = "<output_s3_bucket_from_remote_state_setup>" // e.g., "myclient-tf-state"
   key             = "<account_name>/<main_domain_or_project_name>.tfstate" // e.g., "myclient/example.com.tfstate"
   region          = "<aws_region>" // e.g., "eu-central-1"
   dynamodb_table  = "<output_dynamodb_table_from_remote_state_setup>" // e.g., "myclient-tf-state-locks"
   assume_role = {
       role_arn    = "arn:aws:iam::<aws-account-id>:role/<account_name>-tf-role"
       external_id = "<external_id_if_any>" // Optional
   }
   ```

2. Initialize Terraform for Website Infrastructure:
   Navigate to your account-specific directory:
   ```bash
   # From repository root
   cd infrastructure/accounts/<account_name>
   ```
   Set your AWS_PROFILE to the one configured to assume the Terraform role for this account:
   ```bash
   export AWS_PROFILE=<account_name>-terraform-role
   ```
   Initialize Terraform with the backend configuration:
   ```bash
   tofu init -backend-config=backend.hcl
   ```

3. Manual DNS Steps (First time per domain):
   - **Certificate Validation**: After `tofu apply` (or `plan` if it creates the cert), Terraform will output DNS CNAME records required to validate the ACM certificate. Add these records to your domain's DNS settings (e.g., at your domain registrar or Route 53 if it's managed elsewhere initially). ACM certificates for CloudFront must be in `us-east-1`. The provider alias `aws.certificates` handles this.
   - **Update Name Servers**: Once Route 53 is managing your domain (after the first `tofu apply` creates the hosted zone), update the NS (Name Server) records at your domain registrar to point to the AWS Route 53 name servers shown in the `aws_route53_zone` resource outputs or in the AWS console.

4. Deploy Websites:
   Use the `deploy.sh` script from the repository root to plan and apply changes.
   ```bash
   # Ensure AWS_PROFILE is set correctly
   export AWS_PROFILE=<account_name>-terraform-role

   # Navigate to the account's infrastructure directory where you ran 'tofu init'
   cd infrastructure/accounts/<account_name>/

   # Deploy all stages of a specific website (as defined in your terraform.tfvars)
   ../../cloud_aws/scripts/deploy.sh website example.com

   # Deploy a specific stage of a website
   ../../cloud_aws/scripts/deploy.sh stage example.com dev

   # Deploy everything in the current OpenTofu/Terraform configuration (current directory)
   ../../cloud_aws/scripts/deploy.sh account <account_name>
   # Note: The 'account' argument to deploy.sh is more of a label here;
   # it effectively runs 'tofu plan' and 'tofu apply' in the current directory.
   ```
   The script will run `tofu plan` then `tofu apply` for the specified targets.

## Website Content Management

Place your website content in the directories specified by the `content_path` in your `terraform.tfvars`.
Typically, this follows a structure like:
```
<repository_root>/
└── websites/
    ├── example.com/
    │   ├── dev/
    │   │   └── index.html
    │   │   └── ... (other assets)
    │   ├── preview/
    │   │   └── index.html
    │   └── www/
    │       └── index.html
    └── another-example.com/
        └── www/
            └── index.html
```
The Terraform module expects at least an `index.html` file in each `content_path` directory for the initial deployment of the S3 object. Subsequent content updates can be managed via other means (e.g., CI/CD, `aws s3 sync`), as the `aws_s3_object` for `index.html` in the module has a lifecycle rule to ignore changes to content after creation.

## Testing

1. Run infrastructure tests:
```bash
cd tests
go test -v ./infrastructure/...

```

2. Run drift detection:
```bash
./scripts/drift-detection.sh

```

## Maintenance Mode

To enable maintenance mode for a website:

1. Update the website configuration in `infrastructure/accounts/<account_name>/terraform.tfvars` for the specific stage:
   ```hcl
   # ... inside a stage block ...
   maintenance_mode        = true
   maintenance_allowed_ips = ["YOUR_IP_ADDRESS/32"] // Add IPs that can bypass maintenance
   ```

2. Apply the changes using the deploy script or `tofu apply`:
   ```bash
   # Ensure AWS_PROFILE is set and you are in infrastructure/accounts/<account_name>/
   # To apply to a specific stage:
   ../../cloud_aws/scripts/deploy.sh stage example.com dev
   # Or, if you know the exact target for a single stage (e.g., dev.example.com):
   # tofu apply -target=module.static_website[\"dev.example.com\"]

   # To apply to all stages of a website (if maintenance_mode is set for all):
   # ../../cloud_aws/scripts/deploy.sh website example.com
   ```
   Note: The `deploy.sh` script uses target formats like `module.static_website["example.com-dev"]` or `module.static_website["example.com-*"]`. The actual Terraform module instances are named like `module.static_website["dev.example.com"]`. For precise targeting of a single stage, using the `deployment.full_domain` key (e.g., `dev.example.com`) directly with `tofu apply -target=module.static_website[\"dev.example.com\"]` is more accurate if the script's pattern doesn't match.


## Security Considerations

- All S3 buckets are private and accessed only through CloudFront
- SSL/TLS certificates are automatically managed
- Public access is blocked by default
- IP whitelisting available for maintenance mode
- Infrastructure changes are tracked in remote state with locking

## Common Issues

1. **Certificate Validation**: ACM certificates must be in us-east-1 for CloudFront usage
2. **DNS Propagation**: Allow up to 48 hours for initial DNS propagation
3. **CloudFront Updates**: Distribution updates can take 15-30 minutes

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## License

MIT License - see LICENSE file for details
