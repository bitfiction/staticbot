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
```bash
# Make the script executable
chmod +x scripts/setup-prerequisites.sh
```

# Run for each AWS account

1. Create IAM user <account_name>_assume with IAMFullAccess policy attached via AWS Console
- save users credentials (AWS access and secret key)

2. Setup AWS config profile for user that we will use to assume terraform role
Run:
```bash
aws configure --profile <account_name>-iam

```
and use AWS credentials of user created in previous step

3. Run for the AWS account to setup IAM role
```bash
./scripts/setup-prerequisites.sh <account_name> <account-id>

```

4. Allow <account_name>-iam IAM user to assume <account_name>-terraform-role by adding trust relationship 

On the caller side (IAM user in this case):
```json
{
	"Version": "2012-10-17",
	"Statement": [
		{
			"Sid": "PermissionToAssumeStaticbotDev",
			"Effect": "Allow",
			"Action": "sts:AssumeRole",
			"Resource": "arn:aws:iam::682033486080:role/staticbot-dev-terraform-role"
		}
	]
}
```

On the role to be assumed in the destination account (IAM role in this case):
```json
  {
      "Sid": "<account_name>IamAssume",
      "Effect": "Allow",
      "Principal": {
          "AWS": "arn:aws:iam::111111111111:user/<account_name>_assume"
      },
      "Action": "sts:AssumeRole"
  }

```

5. Add following profile to ~/.aws/config
```bash
[profile <account_name>-terraform-role]
role_arn = arn:aws:iam::111111111111:role/<account_name>-terraform-role
source_profile = <account_name>-iam

```

6. Navigate to remote-state directory
```bash
cd infrastructure/accounts/<account_name>/remote-state

```

7. Initialize and apply for your account

```bash
tofu init
tofu apply

```

8. Configure your websites in `infrastructure/accounts/<account_name>/terraform.tfvars`:
```hcl
websites = {
  "example.com" = {
    domain_name = "example.com"
    aws_account = "account1"
    stages = [
      {
        name      = "dev"
        subdomain = "dev"
        www_redirect = false
        maintenance_mode = false
        maintenance_allowed_ips = []
      },
      {
        name      = "preview"
        subdomain = "preview"
        www_redirect = false
        maintenance_mode = false
        maintenance_allowed_ips = []
      },
      {
        name      = "production"
        subdomain = "www"
        www_redirect = true
        maintenance_mode = false
        maintenance_allowed_ips = []
      }
    ]
  }
}

```

## Deployment

1. Create the backend.hcl file


2. Initialize Terraform with remote state:
```bash
cd infrastructure/accounts/<account_name>

```

3. Validate certificates
- go to AWS Cert Manager console and get the CNAME validation records
- go to your domain registrar (if other than AWS Route53) and set CNAME records as specified in AWS Cert Manager

4. Update Name servers
- update nameservers in your domain registrars Admin interface
- use the Route53 nameservers specified in the domains NS record in Route53


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

1. Update the website configuration in terraform.tfvars
```hcl
  # ... other configuration ...
  maintenance_mode = true
  maintenance_allowed_ips = ["128.0.40.1"]

```

2. Apply the changes:
```bash
tofu apply -target=module.static_website["example.com-*"]

```


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