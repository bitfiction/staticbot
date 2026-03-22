# Self-Hosted Supabase Deployment via Staticbot

## Overview

Deploy self-hosted Supabase to AWS using Staticbot's existing deployment system and worker jobs infrastructure. Each customer gets an isolated Supabase instance running on ECS Fargate with all 13 services.

## Architecture

### Infrastructure (Terraform Template)

The `aws_supabase_self_hosting_template` deploys:

- **VPC** with public/private subnets across 2 AZs
- **ECS Fargate cluster** with 13 services:
  - Core: Auth (GoTrue), PostgREST, Realtime, Storage, imgproxy
  - Data: PostgreSQL, Vector (log shipping)
  - Gateway: Kong (API gateway), Studio (dashboard), postgres-meta, Logflare (analytics), Edge Runtime, Supavisor (connection pooler)
- **ALB** with target groups for Kong (API) and Studio (dashboard)
- **EFS** for persistent storage (DB data, storage files, edge functions)
- **CloudWatch** log groups
- **Service Discovery** via AWS CloudMap (`supabase.internal` namespace)

### Service Communication

All services communicate via CloudMap DNS within the private namespace:
- `db.supabase.internal:5432` — PostgreSQL
- `kong.supabase.internal:8000` — API Gateway
- `rest.supabase.internal:3000` — PostgREST
- `auth.supabase.internal:9999` — GoTrue
- `realtime.supabase.internal:4000` — Realtime
- `storage.supabase.internal:5000` — Storage API
- `imgproxy.supabase.internal:5001` — imgproxy
- `meta.supabase.internal:8080` — postgres-meta
- `analytics.supabase.internal:4000` — Logflare
- `functions.supabase.internal:9000` — Edge Runtime
- `supavisor.supabase.internal:6543` — Connection Pooler

## Deployment Flow

### 1. Template Registration

Register `aws_supabase_self_hosting_template` as a `Template` in Staticbot. Template variables map to Terraform variables in `variables.tf`.

### 2. Stack Composition

Create a `Stack` with a single `StackTemplate` referencing the Supabase template. `configOverrides` carry per-customer values:

**Required secrets:**
- `postgres_password`, `jwt_secret`, `anon_key`, `service_role_key`
- `secret_key_base`, `vault_enc_key`, `pg_meta_crypto_key`
- `logflare_public_access_token`, `logflare_private_access_token`
- `dashboard_password`

**Required URLs:**
- `supabase_public_url`, `api_external_url`, `site_url`

**SMTP config:**
- `smtp_admin_email`, `smtp_host`, `smtp_port`, `smtp_user`, `smtp_pass`

**Optional (opaque API keys):**
- `supabase_publishable_key`, `supabase_secret_key`
- `anon_key_asymmetric`, `service_role_key_asymmetric`

### 3. Deployment Execution

A `Deployment` targeting this Stack follows the existing flow:

**INFRA jobs (Terraform):**
1. `terraform init` + `terraform plan` (DRY_RUN/PLAN)
2. `terraform apply` (APPLY) — creates VPC, ECS, ALB, EFS, CloudMap, all 13 services

**SOFTWARE jobs (post-deploy verification):**
1. `SUPABASE_POST_DEPLOY` job — waits for all ECS services to be healthy, verifies Kong/Studio endpoints, stores connection details

### 4. Worker Job: SUPABASE_POST_DEPLOY

Runs as a migration job after the Supabase infrastructure is deployed. Responsibilities:

1. **Verify ECS health** — Poll all 13 ECS services until healthy (with timeout)
2. **Verify API connectivity** — Hit Kong health endpoint via ALB URL
3. **Verify Studio** — Hit Studio endpoint
4. **Store connection details** — Save ALB URL, anon key, service role key back to migration record for use by Backend Switchover phase

### 5. Integration with Migration Pipeline

The full migration flow with self-hosted target:

| Phase | Name | Description |
|-------|------|-------------|
| 1 | Discovery | Inventory source Supabase project |
| 2 | DB Migration | Migrate schema to self-hosted Postgres (via Supavisor) |
| 3 | Data Import | Import data (manual or automated) |
| 4 | Edge Functions | Deploy to self-hosted Edge Runtime (via EFS or API) |
| 5 | Storage Buckets | Recreate on self-hosted Storage API |
| 6 | Auth Config | Configure self-hosted GoTrue |
| 7 | Backend Switchover | Commit env vars pointing to self-hosted instance |
| 8 | Frontend Deploy | Deploy frontend with updated config |

## Key Design Decisions

### DNS / URL Pattern
Each customer's self-hosted Supabase gets a unique subdomain (e.g., `{project-id}.supabase.staticbot.app`). ALB + Route53 handles routing. `supabase_public_url` and `api_external_url` are set to this URL.

### Secrets Management
Generate `jwt_secret`, `postgres_password`, `anon_key`, `service_role_key` per deployment. Store encrypted using `EncryptionService` in `IntegrationInstance` or a dedicated secrets table.

### Terraform State
Each deployment gets its own state file. Use `backend.tf` with per-deployment S3 key: `s3://staticbot-tf-state/{deployment-id}/terraform.tfstate`.

### Tenant Isolation
Each customer gets their own ECS cluster + VPC. No shared resources between tenants.

### Opaque API Keys (Optional)
Kong 3.9+ supports ES256 opaque API keys (`sb_` prefixed) alongside legacy HS256 JWTs. The `kong-entrypoint.sh` script handles translation. When opaque key variables are empty, the system falls back to legacy-only behavior.

## Implementation Steps

1. Finalize and test Terraform template end-to-end (manual `terraform apply`)
2. Register as a Template in Staticbot's deployment system
3. Add `SUPABASE_POST_DEPLOY` worker job type to Python worker
4. Create Stack definition referencing the template
5. Wire migration pipeline to trigger Supabase deployment as prerequisite
6. Add UI for customer self-hosted Supabase configuration (SMTP, custom domain, etc.)
