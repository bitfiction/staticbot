# CloudFront Reverse Proxy for PostHog

Deploy an AWS CloudFront distribution that proxies analytics requests through your own domain. Designed for [PostHog](https://posthog.com) but works with any HTTP origin.

**Why?** Ad blockers maintain lists of known analytics domains and silently block requests to them. A reverse proxy routes events through your own subdomain, bypassing blockers and increasing event capture by 10-30%. See [PostHog's proxy documentation](https://posthog.com/docs/advanced/proxy) for background.

## What gets created

| Resource | Purpose |
|----------|---------|
| CloudFront Distribution | The proxy — dual origins for API and static assets |
| Cache Policy | Caching disabled (TTL=0) so events forward in real time |
| Origin Request Policy | Whitelists CORS headers without forwarding `Host` (which breaks PostHog) |
| Response Headers Policy | CORS with credentials and explicitly enumerated headers |
| ACM Certificate | SSL for your custom domain (optional, reuses existing if available) |
| Route53 A Record | Alias pointing your subdomain to CloudFront (optional) |

## Architecture

```
Browser → https://e.yourdomain.com
              │
              ▼
         CloudFront
         ├── default → eu.i.posthog.com (API, events, flags)
         └── /static/* → eu-assets.i.posthog.com (JS SDK, assets)
```

## Quick start

### Option A: Interactive script

The included `deploy.sh` script prompts for all required values, generates `terraform.tfvars`, and runs the deployment:

```bash
git clone https://github.com/bitfiction/staticbot.git
cd staticbot/infrastructure/_templates/cloudfront_reverse_proxy_template

./deploy.sh
```

The script will:
1. Detect `tofu` or `terraform` in your PATH
2. Verify AWS credentials
3. Prompt for PostHog region, custom domain, and certificate/hosted zone reuse
4. Validate that custom domains are subdomains (not root domains)
5. Auto-discover existing Route53 hosted zones
6. Generate `terraform.tfvars` and run `init` → `plan` → `apply`

### Option B: Manual deployment

#### Prerequisites

- [OpenTofu](https://opentofu.org/docs/intro/install/) or [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.0
- AWS CLI configured with credentials (`aws sts get-caller-identity`)
- The credentials need permissions for CloudFront, ACM, and Route53

#### 1. Clone and enter the template directory

```bash
git clone https://github.com/bitfiction/staticbot.git
cd staticbot/infrastructure/_templates/cloudfront_reverse_proxy_template
```

#### 2. Create `terraform.tfvars`

**Minimal (no custom domain)** — deploys with a `*.cloudfront.net` URL:

```hcl
project_name   = "my-posthog-proxy"
posthog_region = "eu"   # or "us"
```

**With custom domain and new certificate:**

```hcl
project_name   = "my-posthog-proxy"
posthog_region = "eu"

custom_domain  = "e.example.com"
hosted_zone_id = "Z0123456789ABCDEFGHIJ"
```

**With custom domain, reusing existing hosted zone and certificate:**

```hcl
project_name   = "my-posthog-proxy"
posthog_region = "eu"

custom_domain                   = "e.example.com"
use_existing_hosted_zone        = "true"
use_existing_hosted_zone_id     = "Z0123456789ABCDEFGHIJ"  # optional, auto-detected by parent domain if omitted
use_existing_certificate        = "true"
use_existing_certificate_domain = "*.example.com"
```

**With custom origins (non-PostHog):**

```hcl
project_name         = "my-api-proxy"
api_origin_domain    = "api.backend.com"
assets_origin_domain = "static.backend.com"
```

#### 3. Initialize and apply

```bash
# Initialize with local state (skip the S3 backend)
tofu init -backend=false

# Preview what will be created
tofu plan

# Deploy
tofu apply
```

#### 4. Note the outputs

```
cloudfront_distribution_id = "E1A2B3C4D5E6F7"
cloudfront_domain_name     = "d111111abcdef8.cloudfront.net"
proxy_url                  = "https://e.example.com"
```

## Update your PostHog SDK

Point your SDK to the proxy URL from the outputs:

```js
posthog.init('phc_your_project_token', {
  api_host: 'https://e.example.com',     // your proxy
  ui_host: 'https://eu.posthog.com'      // PostHog's actual domain (for toolbar)
})
```

If your app uses Content Security Policy headers, replace the PostHog domains with your proxy domain in `script-src` and `connect-src`.

## Variables reference

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `project_name` | No | `cloudfront-reverse-proxy` | Name for resource tagging and CloudFront policy naming |
| `posthog_region` | No | `us` | PostHog region: `us` or `eu`. Sets origin domains automatically |
| `api_origin_domain` | No | (from region) | Override the API origin domain |
| `assets_origin_domain` | No | (from region) | Override the assets origin domain |
| `custom_domain` | No | (none) | Custom domain for the distribution. **Must be a subdomain** |
| `hosted_zone_id` | No | (none) | Route53 zone ID. Required when `custom_domain` is set and not using existing zone |
| `use_existing_hosted_zone` | No | `false` | Look up an existing Route53 zone by parent domain name |
| `use_existing_hosted_zone_id` | No | (none) | Explicit zone ID when reusing. If empty, looked up by domain name |
| `use_existing_certificate` | No | `false` | Reuse an existing ACM certificate instead of creating one |
| `use_existing_certificate_domain` | No | (none) | Domain to look up the existing certificate (e.g. `*.example.com`) |
| `cors_allow_origins` | No | `["*"]` | Allowed CORS origins. Restrict to your app's domain in production |
| `price_class` | No | `PriceClass_100` | CloudFront price class (`PriceClass_100`, `_200`, or `_All`) |
| `terraform_role_arn` | No | (none) | IAM role ARN for cross-account deployment (used by Staticbot) |
| `external_id` | No | (none) | External ID for role assumption |

## Common pitfalls

**Root domain as custom domain.** Using `example.com` instead of `e.example.com` overwrites your website's DNS records. The deploy script and Staticbot both validate against this.

**Host header forwarding.** If the origin request policy forwards all viewer headers, CloudFront sends `Host: yourdomain.com` to PostHog instead of `Host: eu.i.posthog.com`. PostHog returns 404. This template uses whitelisted headers to avoid this.

**Cache policy with caching disabled.** CloudFront requires cookie, header, and query string behaviors to be `none` when TTL is 0. Setting them to `all` causes `InvalidArgument` errors. This template sets them correctly.

**CORS wildcard with credentials.** `Access-Control-Allow-Headers: *` is invalid when `Access-Control-Allow-Credentials: true`. This template lists headers individually.

**ACM certificate region.** CloudFront requires certificates in `us-east-1` regardless of your region. This template's provider is already set to `us-east-1`.

## Destroy

To tear down all resources:

```bash
tofu destroy
```

## Automated deployment with Staticbot

If you'd rather not manage Terraform yourself, [Staticbot](https://staticbot.dev) automates the entire process through a deployment wizard:

- Runs pre-checks to discover existing certificates and hosted zones in your AWS account
- Validates domains (prevents root domain misuse)
- Deploys via OpenTofu with state stored in your account (S3 + DynamoDB)
- Supports redeployment, plan previews, and teardown from the UI

Read more: [Deploy a PostHog Reverse Proxy on AWS CloudFront — The Easy Way](https://staticbot.dev/blog/posthog-proxy-deployment)

## License

MIT License. See [LICENSE](../../../LICENSE) for details.
