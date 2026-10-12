# AWS Supabase Self-Hosting Template

Deploys a single-tenant Supabase stack on AWS ECS Fargate, ported from upstream's `docker/docker-compose.yml` plus `docker-compose.logs.yml`. See `docs/features/self-hosted-supabase-deployment.md` for how it fits into Staticbot.

## Architecture

```
Internet → ALB (HTTP :80) → Envoy (api-gw) → Supabase services (Cloud Map: <name>.supabase.internal)
                                           → Studio (basic auth)
```

- **Networking**: VPC with public/private subnets in 2 AZs; all tasks run in private subnets; only the ALB is public.
- **Service discovery**: AWS Cloud Map private namespace `supabase.internal`. Fargate tasks don't resolve bare service names, so every in-stack address (including Envoy's clusters) uses `<name>.supabase.internal`.
- **Storage**: EFS with one access point each for Postgres data (`/db`), `/etc/postgresql-custom` (`/db-config`, incl. the pgsodium/Vault root key), storage files, edge functions and Studio snippets.
- **Logs**: CloudWatch (`awslogs` driver).

## Services

| Service | Image |
|---------|-------|
| PostgreSQL | supabase/postgres:17.6.1.136 (15.8.1.085 with `postgres_version = "15"`) |
| API gateway | envoyproxy/envoy:v1.39.1 |
| Auth | supabase/gotrue:v2.196.0 |
| PostgREST | postgrest/postgrest:v14.17 |
| Realtime | supabase/realtime:v2.134.10 |
| Storage / ImgProxy | supabase/storage-api:v1.74.0 / darthsim/imgproxy:v3.31.4 |
| Studio | supabase/studio:2026.09.07-sha-7996410 |
| Meta | supabase/postgres-meta:v0.99.0 |
| Analytics | supabase/logflare:1.50.10 |
| Functions | supabase/edge-runtime:v1.76.2 |
| Supavisor | supabase/supavisor:2.9.12 |
| Vector | timberio/vector:0.53.0-alpine |

## How config files reach the tasks

Terraform reads files from `docker/` (upstream's mirror) and injects them as environment variables; each task's command writes them to the expected paths before starting:

- Postgres init SQL is written next to the image's own `init-scripts/` and `migrations/`, as compose mounts it.
- Envoy configs and the Edge Functions seed files are shipped gzip+base64 (`base64gzip()`), because `lds.template.yaml` alone is ~55 KB and an ECS task definition is capped at 64 KB.
- Edge Functions: `main/` is rewritten on every start (template-owned router); `hello/` and `deno.jsonc` are only seeded once.

## Configuration notes

- `postgres_version` defaults to `"17"`. An existing PG15 data directory needs `"15"` until it's upgraded with `docker/utils/upgrade-pg17.sh`. The `/db` access point's POSIX identity follows the version (PG15 runs postgres as 105:106, PG17 as 100:101); Postgres refuses a data directory it doesn't own.
- `api_external_url` is optional; it includes `/auth/v1` since self-hosted 0.7.0, and a value without it gets it appended.
- `realtime_db_enc_key` defaults to upstream's fallback `supabaserealtime`; set a random 16-character value for new deployments.
- New API keys: set `supabase_publishable_key`, `supabase_secret_key`, `anon_key_asymmetric`, `service_role_key_asymmetric`, `jwt_keys` and `jwt_jwks` (from `docker/utils/add-new-auth-keys.sh`).

## Known Gaps

- **No TLS**: the ALB listens on HTTP :80 only. Add an ACM certificate and an HTTPS listener before production use.
- **Logs Explorer is empty**: upstream's Vector config reads Docker container logs, which Fargate doesn't expose; logs only reach CloudWatch. Shipping them to Logflare needs FireLens or a CloudWatch subscription.
- Secrets are passed as plain task environment variables, not via Secrets Manager.

## Files

| File | Purpose |
|------|---------|
| `main.tf` | Provider, locals (image per Postgres major, URLs) |
| `variables.tf` | All configurable variables |
| `network.tf` | VPC, subnets, NAT, security groups, ALB + API gateway target group |
| `ecs.tf` | ECS cluster, Cloud Map namespace, IAM roles |
| `efs.tf` | EFS file system and access points |
| `logs.tf` | CloudWatch log group |
| `ecs-services-data.tf` | PostgreSQL, Vector |
| `ecs-services-core.tf` | Auth, PostgREST, Realtime, Storage, ImgProxy |
| `ecs-services-gateway.tf` | Envoy, Studio, Meta, Analytics, Functions, Supavisor |
| `outputs.tf` | ALB DNS name, API/Studio URLs |
| `remote-state/` | S3 + DynamoDB for this deployment's state |
| `docker/` | Mirror of upstream `supabase/supabase` `docker/` — never edit by hand; `supabase-sync.py` overwrites it |

## Upstream Sync

Kept in sync with the other Supabase templates by `scripts/supabase-sync.py`. See the DO single-tenant template's README for the workflow.
