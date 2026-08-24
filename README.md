<h1 align="center">Staticbot</h1>

<p align="center">
  <strong>Build with AI tools. Run the production stack on infrastructure you control.</strong>
  <br />
  Migrate AI-built apps to your own Supabase, deploy the frontend to Cloudflare Workers or AWS,
  <br />
  and optionally keep every future change in sync.
</p>

<p align="center">
  <a href="https://www.staticbot.dev/"><strong>Website</strong></a> ·
  <a href="https://app.staticbot.dev/"><strong>Dashboard</strong></a> ·
  <a href="https://www.staticbot.dev/guides"><strong>Guides</strong></a> ·
  <a href="https://www.staticbot.dev/templates"><strong>Templates</strong></a> ·
  <a href="https://www.staticbot.dev/platform/api-access"><strong>API</strong></a> ·
  <a href="https://www.staticbot.dev/platform/mcp-server"><strong>MCP server</strong></a>
</p>

---

Staticbot is a deployment and migration platform for apps created with Lovable, Bolt, Base44, v0, Manus, and conventional GitHub workflows. It separates the editor from the runtime: keep building in the tool you prefer while your database, authentication, storage, functions, and frontend run on infrastructure selected for the application.

This repository contains the open infrastructure modules and templates used to provision those runtimes. When you select bring-your-own-cloud or self-hosted infrastructure, the OpenTofu/Terraform configuration is inspectable and portable, and the deployed infrastructure can continue running without Staticbot.

## What Staticbot does today

- **Migrates complete backends** — move database schema and data, Supabase Auth users and OAuth identities, Row Level Security policies, Edge Functions, Storage buckets and files, Vault secrets, cron jobs, and auth configuration.
- **Supports managed and self-hosted Supabase targets** — migrate into a Supabase Cloud project you own, or download an AES-256-encrypted migration package containing ordered SQL, functions, storage objects, identities, secrets, cron jobs, and verification instructions for a self-hosted instance.
- **Handles builder-specific differences** — dedicated migration paths cover Lovable/Supabase, Bolt/Supabase, Firebase, Base44 apps already using Supabase, and native Base44 apps using `@base44/sdk`. Native Base44 migrations synthesize PostgreSQL tables from entity schemas and replace the proprietary SDK through a Supabase-backed compatibility shim.
- **Creates a working preview before cutover** — the migrated app is built against the new backend and deployed to a live preview URL for verification. The production app is unchanged until you approve the switchover.
- **Chooses the appropriate frontend runtime** — static sites and SPAs deploy to AWS S3 + CloudFront; full-stack and SSR applications deploy to Cloudflare Workers. Supported Worker builds include TanStack Start, Nuxt, SolidStart, Astro with the Cloudflare adapter, and other frameworks that produce a Worker bundle.
- **Keeps production in sync** — optional Continuous Sync watches the connected GitHub repository and applies new SQL migrations in order, deploys changed Edge Functions, then rebuilds the frontend. Automatic, manual, and paused modes are supported, and a dedicated `staticbot/live` branch leaves the builder-managed branch untouched.
- **Adds safety to long-running operations** — discovery inventories the source before writing, destructive database changes pause for review, failures retain their state for retry, and template/deployment versions are pinned to Git commit SHAs.
- **Supports custom domains and staged delivery** — use managed hosting or your own AWS account, with TLS, DNS guidance, redirects, maintenance mode, previews, rollbacks, and independent deployment stages where the selected template supports them.

## From AI builder to owned runtime

The standard workflow is:

1. Connect the app's GitHub repository and the source integration.
2. Select a Supabase Cloud project you own or a self-hosted Supabase target.
3. Run discovery and review the inventory before approving any migration work.
4. Migrate the backend in phases and deploy a working preview against it.
5. Test the real application, then choose when to switch the frontend and backend over.
6. Optionally enable Continuous Sync so later builder or repository changes flow to production.

Staticbot applies database migrations sequentially, deploys independent Edge Functions in parallel, and rebuilds the frontend last. Potentially destructive SQL such as `DROP TABLE` or column-altering operations pauses for explicit review. Each sync records the source and target commits plus an inventory of what changed.

The frontend destination is based on the project type:

| Project type | Deployment target | Runtime characteristics |
|---|---|---|
| Static HTML, Vite/React SPA, JAMstack build | AWS S3 + CloudFront | Object storage, global CDN, ACM TLS, redirects, and build-time public environment variables |
| TanStack Start, Nuxt, SolidStart, Astro/Cloudflare, Hono, other SSR or full-stack Worker builds | Cloudflare Workers | SSR and server functions at the edge, runtime secrets, custom hostnames, and global routing |

## Infrastructure templates

The [`infrastructure/_templates`](./infrastructure/_templates) directory contains the versioned infrastructure definitions used by Staticbot. Some are ready for direct use; others are lower-level platform templates whose values and shared dependencies are normally supplied by Staticbot's deployment workers.

| Template | What it deploys | Highlights | Intended use |
|---|---|---|---|
| [`static_website_infra_template`](./infrastructure/_templates/static_website_infra_template) | Static websites on AWS S3 + CloudFront using a root domain | Multiple stages per site, `www` redirects, custom redirects, maintenance mode with allowed IPs, certificate and Route 53 reuse | Direct OpenTofu/Terraform use or Staticbot-managed deployment |
| [`static_website_on_subdomain_infra_template`](./infrastructure/_templates/static_website_on_subdomain_infra_template) | Static websites on AWS S3 + CloudFront using a subdomain | Supports nested subdomains, existing certificates/zones, redirects, maintenance mode, and CloudFront/S3 outputs | Direct OpenTofu/Terraform use or Staticbot-managed deployment |
| [`cloudflare_workers_app_template`](./infrastructure/_templates/cloudflare_workers_app_template) | One full-stack or SSR application on Cloudflare Workers for Platforms | Framework-agnostic Worker routing, KV hostname mapping, SSL for SaaS custom hostname enrollment, secrets kept out of Terraform state | Staticbot platform building block; the Worker bundle is deployed separately with Wrangler |
| [`cloudfront_reverse_proxy_template`](./infrastructure/_templates/cloudfront_reverse_proxy_template) | A CloudFront reverse proxy for PostHog or another HTTP origin | Separate API/assets origins, no-cache event forwarding, CORS policies, optional ACM certificate and Route 53 record, existing certificate/zone reuse | Standalone interactive script, direct OpenTofu/Terraform, or Staticbot deployment |
| [`aws_supabase_self_hosting_template`](./infrastructure/_templates/aws_supabase_self_hosting_template) | A self-hosted Supabase stack on AWS | ECS services in private subnets, Application Load Balancer, EFS persistence, Cloud Map service discovery, CloudWatch logs, PostgreSQL, Auth, REST, Realtime, Storage, Functions, Studio, Analytics, and Supavisor | Self-hosted Supabase in an AWS account you control |
| [`do_supabase_self_hosting_template`](./infrastructure/_templates/do_supabase_self_hosting_template) | A complete Supabase stack on DigitalOcean Kubernetes | DOKS, nginx ingress, cert-manager TLS, Block Storage, PostgreSQL, Kong, Auth, REST, Realtime, Storage, Functions, Studio, Analytics, and Supavisor | Standalone single-tenant self-hosted Supabase; supports local state for testing and Spaces-backed remote state |
| [`do_supabase_multi_tenant_tenant`](./infrastructure/_templates/do_supabase_multi_tenant_tenant) | Per-tenant Supabase services in a shared DOKS cluster | Isolated Kubernetes namespace, Auth, PostgREST, Storage, Edge Functions, database provisioning, and registration with shared Realtime/Supavisor | Staticbot multi-tenant platform component; requires the shared cluster to exist first |

### Static website templates

Both static-site templates call the reusable [`static_website_custom_domain`](./infrastructure/cloud_aws/root_modules/static_website_custom_domain) module. They provision S3 origins and CloudFront distributions and expose website URLs, bucket names, distribution IDs, endpoints, and DNS nameservers. Use the root-domain variant when Staticbot manages one or more stages such as `dev`, `preview`, and `www` beneath a registered domain; use the subdomain variant when deploying an independent site at a specific hostname such as `docs.example.com` or `app.preview.example.com`.

### Cloudflare Workers application template

The Workers template enrolls one customer application into a shared Workers for Platforms deployment. Terraform manages the hostname-to-Worker KV route and Cloudflare Custom Hostname/TLS enrollment. Framework-specific build outputs and compatibility flags remain application metadata, while Wrangler uploads the actual Worker and pushes sensitive secrets separately so they do not enter Terraform state.

### CloudFront reverse proxy template

The reverse-proxy template is configured for PostHog by default, routing API traffic and static assets through separate origins on a first-party subdomain. It can also proxy arbitrary HTTP origins. Its included `deploy.sh` detects OpenTofu or Terraform, validates AWS credentials and domain choices, discovers reusable Route 53 zones, and runs the deployment interactively. See the [template guide](./infrastructure/_templates/cloudfront_reverse_proxy_template/README.md) for variables and examples.

### Self-hosted Supabase templates

The AWS and DigitalOcean templates deploy the Supabase runtime rather than only a frontend. They are useful when data residency, VPC or cluster ownership, extension control, or avoiding a managed backend is a requirement. The AWS implementation uses ECS, EFS, private networking, Cloud Map, and an ALB. The DigitalOcean implementation uses DOKS, Kubernetes storage, nginx ingress, and cert-manager. Their checked-in configuration and image versions are periodically synchronized with the upstream Supabase Docker distribution; review each template's README and plan before applying updates.

The DigitalOcean per-tenant template is not a standalone Supabase cluster. It adds an isolated tenant namespace and services to shared infrastructure and expects cluster credentials, database endpoints, ingress domains, and shared Realtime/Supavisor services from that parent environment.

## Using a template directly

Requirements vary by template, but the common flow is:

```bash
git clone https://github.com/bitfiction/staticbot.git
cd staticbot/infrastructure/_templates/<template-name>

# Use the variable seed file supplied by the selected template.
cp terraform.tfvars.example terraform.tfvars
# Some templates provide terraform.tfvars.template instead.

# Follow the template README to configure local or remote state.
tofu init
tofu plan
tofu apply
```

Read the selected template's README first. Several templates use a remote backend in Staticbot production, accept cross-account credentials, or depend on shared infrastructure. For local evaluation, configure an explicit local backend only where the template guide supports it. Never commit populated `terraform.tfvars`, backend credentials, service-role keys, or migration package passwords.

For the existing AWS static-site workflow, see the [AWS infrastructure deployment guide](./infrastructure/cloud_aws/README.md).

## API and MCP automation

Staticbot's core workflows can be driven by agents and automation through the [Staticbot REST API](https://www.staticbot.dev/platform/api-access) and the open-source [`staticbot-mcp`](https://github.com/bitfiction/staticbot-mcp) server.

The MCP server lets Claude Code, Cursor, and other MCP-compatible clients:

- inspect and create templates from GitHub repositories;
- create stacks and start or monitor deployments;
- run Lovable, Bolt, Firebase, and Base44 migration pipelines;
- inspect discovery inventories and respond to approval or choice gates;
- create migration previews and download self-hosted migration packages;
- inspect connected projects, trigger syncs, review destructive changes, retry failures, and manage sync modes;
- roll back, redeploy, and manage automatic updates for deployed websites.

Template versions are pinned to Git commits, stacks bind to explicit versions, and sync runs record the exact commit transition. This makes deployments reproducible and gives operators an audit trail from repository change to production runtime.

## Learn more

- [Migrate Lovable to Supabase](https://www.staticbot.dev/deployment-guides/ai-tools/lovable-supabase-migration)
- [Migrate Base44 to Supabase](https://www.staticbot.dev/deployment-guides/ai-tools/base44-supabase-migration)
- [Migrate Firebase to Supabase](https://www.staticbot.dev/migration-guides/firebase-supabase)
- [Migrate to self-hosted Supabase](https://www.staticbot.dev/migration-guides/self-hosted-supabase)
- [Deploy a Supabase frontend](https://www.staticbot.dev/deployment-guides/backend/supabase)
- [Continuous Sync](https://www.staticbot.dev/solutions/continuous-sync)
- [Current pricing](https://www.staticbot.dev/pricing)
