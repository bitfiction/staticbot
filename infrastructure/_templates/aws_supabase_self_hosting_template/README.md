# AWS Supabase Self-Hosting Template

Deploys a single-tenant Supabase stack on AWS ECS Fargate, ported from upstream's `docker/docker-compose.yml` plus `docker-compose.logs.yml`. See `docs/features/self-hosted-supabase-deployment.md` for how it fits into Staticbot.

## Architecture

```
Internet → ALB (HTTP :80) → Envoy (api-gw) → Supabase services (Cloud Map: <name>.supabase.internal)
                                           → Studio (basic auth)
```

- **Networking**: VPC with public/private subnets in 2 AZs; all tasks run in private subnets; only the ALB is public.
- **Service discovery**: AWS Cloud Map private namespace `supabase.internal`. Fargate tasks don't resolve bare service names, so every in-stack address (including Envoy's clusters) uses `<name>.supabase.internal`.
- **Storage**: EFS with one access point each for Postgres data (`/db`), `/etc/postgresql-custom` (`/db-config`, incl. the pgsodium/Vault root key), backup state (`/db-backup-state`), storage files, edge functions and Studio snippets.
- **Backups**: WAL-G to an S3 bucket in this account (`backups.tf`); see below.
- **Logs**: CloudWatch (`awslogs` driver).

## Services

| Service | Image |
|---------|-------|
| PostgreSQL | supabase/postgres:17.6.1.136 (+ backup and migrate containers) |
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

- Postgres init SQL and the `db-lifecycle/` scripts are shipped gzip+base64 in the db task's `prepare` container, which unpacks them (and WAL-G) into task volumes; the db container puts the init SQL next to the image's own `init-scripts/` and `migrations/`, as compose mounts it.
- Envoy configs and the Edge Functions seed files are shipped gzip+base64 (`base64gzip()`), because `lds.template.yaml` alone is ~55 KB and an ECS task definition is capped at 64 KB.
- Edge Functions: `main/` is rewritten on every start (template-owned router); `hello/` and `deno.jsonc` are only seeded once.

## Configuration notes

- Postgres 17 only. The db container refuses a data directory from another major. The `/db` access point runs as the image's postgres user (100:101); Postgres refuses a data directory it doesn't own.
- `api_external_url` is optional; it includes `/auth/v1` since self-hosted 0.7.0, and a value without it gets it appended.
- `realtime_db_enc_key` defaults to upstream's fallback `supabaserealtime`; set a random 16-character value for new deployments.
- New API keys: set `supabase_publishable_key`, `supabase_secret_key`, `anon_key_asymmetric`, `service_role_key_asymmetric`, `jwt_keys` and `jwt_jwks` (from `docker/utils/add-new-auth-keys.sh`).

## Database upgrades and backups

Same mechanism as every Staticbot Supabase template (`db-lifecycle/README.md`), as containers in the db task:

| Container | Runs | Role |
|-----------|------|------|
| `prepare` | once, before `db` | Copies WAL-G and unpacks the lifecycle scripts and init SQL |
| `db` | always (essential) | Postgres with `archive_command = wal-g wal-push`; first boot records the schema baseline |
| `backup` | always, after `db` is healthy | Daily base backup (14 kept), Vault key upload, archive-failure alerts in its log |
| `migrate` | once per task start, after `db` is healthy | Applies pending image/template migrations; a no-op when nothing is pending |

`backup` and `migrate` aren't essential: a failure shows in their CloudWatch streams (`db-backup/…`, `db-migrate/…`) but doesn't stop Postgres. Check `db-migrate` after every image bump: it refuses to run while a new image migration has no `apply`/`skip` decision.

Backups go to an S3 bucket in this account (`backups.tf`: versioned, encrypted, public access blocked) with an IAM user that can only reach that bucket. The deploying credentials therefore need `s3:CreateBucket` and `iam:CreateUser`/`PutUserPolicy`/`CreateAccessKey` on top of what the stack already used.

### Restoring

`db-restore` is a task definition, not a service. Stop the database, run it, start the database again:

```bash
CLUSTER=$(tofu output -raw ecs_cluster)
TASK=$(tofu output -raw db_restore_task_definition)
SUBNETS=$(tofu output -json private_subnet_ids | jq -r 'join(",")')
SG=$(tofu output -raw ecs_tasks_security_group_id)
TARGET="2026-06-14 09:30:00+00"     # just before the incident (UTC); empty = latest

aws ecs update-service --cluster $CLUSTER --service db --desired-count 0 >/dev/null
aws ecs wait services-stable --cluster $CLUSTER --services db

aws ecs run-task --cluster $CLUSTER --task-definition $TASK --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$SG],assignPublicIp=DISABLED}" \
  --overrides "{\"containerOverrides\":[{\"name\":\"restore\",\"environment\":[{\"name\":\"RECOVERY_TARGET_TIME\",\"value\":\"$TARGET\"}]}]}"

aws logs tail $(tofu output -raw log_group_name) --follow --log-stream-name-prefix db-restore   # ends with "restore complete"

aws ecs update-service --cluster $CLUSTER --service db --desired-count 1 >/dev/null
```

Don't run `tofu apply` while the service is scaled to 0 (it would set `desired_count` back to 1). A `RECOVERY_TARGET_TIME` later than the archive's last transaction fails with a message saying how far the archive goes. The previous data stays on EFS as `/db.before-restore-<timestamp>`; delete it (e.g. from an ECS Exec session in a task that mounts the file system root) once the restore checks out.

## Known Gaps

- **No TLS**: the ALB listens on HTTP :80 only. Add an ACM certificate and an HTTPS listener before production use.
- **Logs Explorer is empty**: upstream's Vector config reads Docker container logs, which Fargate doesn't expose; logs only reach CloudWatch. Shipping them to Logflare needs FireLens or a CloudWatch subscription.
- Secrets are passed as plain task environment variables, not via Secrets Manager.

## Files

| File | Purpose |
|------|---------|
| `main.tf` | Provider, locals (Postgres image, URLs, WAL-G settings) |
| `variables.tf` | All configurable variables |
| `network.tf` | VPC, subnets, NAT, security groups, ALB + API gateway target group |
| `ecs.tf` | ECS cluster, Cloud Map namespace, IAM roles |
| `efs.tf` | EFS file system and access points |
| `backups.tf` | S3 bucket + bucket-scoped IAM user for WAL-G backups |
| `logs.tf` | CloudWatch log group |
| `ecs-services-data.tf` | PostgreSQL task (prepare, db, backup, migrate), db-restore task, Vector |
| `db-lifecycle/` | Copy of `_shared/supabase-db-lifecycle` (schema upgrades, backups, restore); don't edit here |
| `ecs-services-core.tf` | Auth, PostgREST, Realtime, Storage, ImgProxy |
| `ecs-services-gateway.tf` | Envoy, Studio, Meta, Analytics, Functions, Supavisor |
| `outputs.tf` | ALB DNS name, API/Studio URLs |
| `remote-state/` | S3 + DynamoDB for this deployment's state |
| `docker/` | Mirror of upstream `supabase/supabase` `docker/` — never edit by hand; `supabase-sync.py` overwrites it |

## Upstream Sync

Kept in sync with the other Supabase templates by `scripts/supabase-sync.py`. See the DO single-tenant template's README for the workflow.
