# Multi-Tenant Supabase — Per-Tenant Template

Deploys per-tenant Supabase services into a `tenant-{id}` namespace on the shared DOKS cluster. Executed by Staticbot's tf-runner for each new tenant.

## What Gets Deployed

| Service | Image | Resources (req/limit) |
|---------|-------|-----------------------|
| GoTrue (Auth) | supabase/gotrue:v2.186.0 | 30m/100Mi → 100m/256Mi |
| PostgREST | postgrest/postgrest:v14.8 | 30m/100Mi → 100m/256Mi |
| Storage API | supabase/storage-api:v1.48.26 | 50m/128Mi → 150m/384Mi |
| Edge Functions | supabase/edge-runtime:v1.71.2 | 40m/100Mi → 150m/384Mi |

Plus two provisioning jobs (`wait_for_completion = true`):
1. **DB provisioning** — Creates `tenant_{id}` database, runs SQL init scripts, sets JWT secret
2. **Service registration** — Registers tenant with shared Realtime and Supavisor

## Prerequisites

The shared cluster must be deployed first via `staticbot-control-center/infra/digitalocean/modules-tenants/shared/`. This template receives cluster credentials and shared service hostnames as variables.

## Key Variables

| Variable | Source | Purpose |
|----------|--------|---------|
| `tenant_id` | Migration pipeline | Unique tenant identifier |
| `cluster_endpoint`, `cluster_token`, `cluster_ca_cert` | Shared module outputs | K8s cluster access |
| `shared_db_host`, `shared_db_port` | Shared module outputs | PostgreSQL connection |
| `api_domain` | Shared module outputs | e.g. `sb.frever.net` |
| `jwt_secret`, `anon_key`, `service_role_key` | Generated per tenant | Tenant-specific secrets |

## Files

| File | Purpose |
|------|---------|
| `main.tf` | Providers (standalone — tf-runner runs this directly) |
| `variables.tf` | All variables (tenant config + shared infra references) |
| `k8s-namespace.tf` | `tenant-{id}` namespace, Secrets, functions PVC |
| `k8s-services.tf` | GoTrue, PostgREST, Storage API, Edge Functions |
| `k8s-provisioning.tf` | DB creation job + service registration job |
| `outputs.tf` | tenant_id, api_url, keys |
| `docker/volumes/db/*.sql` | SQL init scripts mounted in provisioning job |

## Upstream Sync

Image versions come from the upstream `supabase/supabase` repo. The sync script updates this template alongside all others:

```bash
cd ~/Dev/Workspaces/staticbot/supabase/supabase && git pull
cd ~/Dev/Workspaces/staticbot/staticbot
python scripts/supabase-sync.py detect        # see what changed
python scripts/supabase-sync.py apply --safe   # updates k8s-services.tf + k8s-provisioning.tf
```
