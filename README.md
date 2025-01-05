# Multi-Account Static Website Infrastructure

This repository contains infrastructure as code for managing multiple static websites across different AWS accounts, with support for multiple deployment stages (dev, preview, www) per website.

## Initiate directory structure

mkdir -p scripts infrastructure/{businesses/{example,another-example},modules/{static-website,backend},remote-state} websites/{example.com,example.org,another-example.com}/{dev,preview,www} tests/infrastructure

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
```bash
# Make the script executable
chmod +x scripts/setup-prerequisites.sh
```

# Run for each AWS account

1. Create IAM user <business>_assume with IAMFullAccess policy attached via AWS Console
- save users credentials (AWS access and secret key)

2. Setup AWS config profile for user that we will use to assume terraform role
Run:
```bash
aws configure --profile <business>-iam

```
and use AWS credentials of user created in previous step

3. Run for the AWS account to setup IAM role
```bash
./scripts/setup-prerequisites.sh <business> <account-id>

```

4. Allow <business>-iam IAM user to assume <business>-terraform-role by adding trust relationship 
```json
  {
      "Sid": "<business>IamAssume",
      "Effect": "Allow",
      "Principal": {
          "AWS": "arn:aws:iam::111111111111:user/<business>_assume"
      },
      "Action": "sts:AssumeRole"
  }

```

5. Add following profile to ~/.aws/config
```bash
[profile <business>-terraform-role]
role_arn = arn:aws:iam::111111111111:role/<business>-terraform-role
source_profile = <business>-iam

```

6. Navigate to remote-state directory
```bash
cd infrastructure/remote-state

```

7. Initialize and apply for your business/environment

```bash
cd infrastructure/remote-state
tofu init
tofu apply -var="business=<business>" -var="terraform_role_arn=arn:aws:iam::111111111111:role/prod-terraform-role"

```

8. Configure your websites in `infrastructure/businesses/<env>/terraform.tfvars`:
```hcl
websites = {
  "example.com" = {
    domain_name = "example.com"
    aws_account = "account1"
    stages = [
      {
        name      = "dev"
        subdomain = "dev"
      },
      {
        name      = "preview"
        subdomain = "preview"
      },
      {
        name      = "production"
        subdomain = "www"
      }
    ]
  }
}

```

## Deployment

1. Create the backend.hcl file


2. Initialize Terraform with remote state:
```bash
cd infrastructure/businesses/<business>

```

# Initialize with backend config
tofu init -backend-config=backend.hcl

```

2. Deploy websites:
```bash
# Deploy all stages of a specific website
./scripts/deploy.sh website example.com

# Deploy a specific stage
./scripts/deploy.sh stage example.com dev

# Deploy everything in an account
./scripts/deploy.sh account account1

```

## Website Content Management

Place your website content in the appropriate directories:
```
websites/
├── example.com/
│   ├── dev/
│   ├── preview/
│   └── www/
└── another-example.com/
    ├── dev/
    ├── preview/
    └── www/

```

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

1. Update the website configuration:
```hcl
module "static_website" {
  # ... other configuration ...
  maintenance_mode = true
  maintenance_allowed_ips = ["203.0.113.1"]
}

```

2. Apply the changes:
```bash
tofu apply -target=module.static_website["example.com-*"]

```

3. Validate certificates
- go to AWS Cert Manager console and get the CNAME validation records
- go to your domain registrar (if other than AWS Route53) and set CNAME records as specified in AWS Cert Manager

4. Update Name servers
- update nameservers in your domain registrars Admin interface
- use the Route53 nameservers specified in the domains NS record in Route53


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