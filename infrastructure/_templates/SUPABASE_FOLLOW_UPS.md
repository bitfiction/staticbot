# Supabase templates: follow-ups

Open work after the 2026-10-12 upstream sync (self-hosted 0.8.2, Envoy, Postgres 17), the per-tenant Postgres redesign and the schema-upgrade and backup work (`_shared/supabase-db-lifecycle`). Everything below was validated with `tofu validate` and Docker only, never on real DOKS, ECS or Spaces.

Branches: staticbot `chore/supabase-sync-2026-10-12`, staticbot-control-center `chore/supabase-mt-per-tenant-postgres`.

## 1. Before the first multi-tenant test run

- [ ] **staticbot-app: new migration for the tenant template.** `V20260416100000__create_multi_tenant_supabase_template.sql` registers it with the old path and variables:
  - `repo_path`: `infrastructure/_templates/do_supabase_multi_tenant_tenant` → `infrastructure/_templates/do_supabase_multi_tenant_template` (renamed).
  - Add the required variables: `shared_api_jwt_secret`, `wal_g_image`, `backup_s3_bucket`, `backup_s3_region`, `backup_s3_access_key_id`, `backup_s3_secret_access_key`. Also add `image_pull_secret_name`, which is optional but needed with the DOCR image. All come from the tenants env outputs.
  - Remove `shared_db_host`, `shared_db_port` and `shared_imgproxy_host`. Tenants now run their own Postgres, and the ImgProxy host is derived from `shared_namespace`.
  - Bump the pinned commit.
- [ ] **Tenants env tfvars** (`prod-tenants`, `qa-tenants`): `aws_access_key_id`, `aws_secret_access_key`, `aws_region`, `tenant_backup_bucket_name`, `registry_name`, `wal_g_image`.
- [ ] **WAL-G image in DOCR**: `scripts/build_and_push_do_images.sh -e prod -i wal-g` (and `-e qa`).
- [ ] **tf-runner**: provision tenants with the per-tenant template. Nothing does this today.
- [ ] **DOKS version**: the shared module's `k8s_version` default `1.31.1-do.5` (prod-tenants sets `1.33.1-do.3`) is probably no longer offered. Check `doctl kubernetes options versions`.

## 2. Before rolling out the single-tenant changes

- [ ] **Public WAL-G image**: merging control-center to `main` runs `publish-wal-g.yml`, which publishes `ghcr.io/bitfiction/wal-g:v3.0.9`. Make the package public once in the GitHub package settings, then check that both architectures pull (`docker pull --platform linux/arm64 ...`). The DO and AWS templates default to this image.
- [ ] **AWS Template registration** (`V20260322140000__create_self_hosted_supabase_template.sql`):
  - Bump the pinned commit `a32fe46`.
  - The description still says Kong.
  - `domain_name` is registered but isn't a template variable. This predates the sync.
- [ ] **AWS deploy credentials** now also need S3 bucket creation (versioning, encryption, lifecycle, public access block) plus `iam:CreateUser`, `PutUserPolicy` and `CreateAccessKey` for the backup user.
- [ ] **DO single-tenant registration**: none exists yet. When adding one:
  - Pass the customer's Spaces key as `spaces_access_id`/`spaces_secret_key`, or set `SPACES_ACCESS_KEY_ID`/`SPACES_SECRET_ACCESS_KEY` in tf-runner. The backup bucket can't be created with the DO API token alone.
  - Don't pass `postgres_version`; it was removed.
  - Check the `k8s_version` default (`1.31.1-do.5`).

## 3. Verify on real infrastructure

- [ ] **DOKS**:
  - Cilium enforces the NetworkPolicies (tenant isolation, shared services).
  - The DOCR integration pull secret appears in new tenant namespaces.
  - The backup sidecar and migrate Job run.
  - The restore runbooks work, for a tenant and for the shared DB, as a deliberate drop-and-restore drill.
- [ ] **ECS (AWS template)**:
  - Container ordering in the db task: `prepare` SUCCESS, then `db` HEALTHY, then `backup` and `migrate`.
  - EFS access points work as uid 100.
  - The `db-restore` task works with the EFS root mount.
  - Deployments run with 0% minimum and 100% maximum.
- [ ] **DO Spaces**: the versioning and noncurrent-version-expiration lifecycle rules are accepted and honored, and WAL-G works with the bucket-scoped key.
- [ ] **Per-tenant E2E** against a real tenant: the same 18 checks that passed in Docker (legacy and `sb_` keys, ES256, RLS, Realtime through the shared service, Storage, Functions, gateway restrictions).

## 4. Hardening and design debt

- [ ] **One backup key for everything**: every tenant and the shared DB use the same IAM key. A leaked tenant namespace Secret exposes all archives. Before real tenants arrive, switch to per-tenant credentials scoped to `tenants/<id>/*`, e.g. an IAM user per tenant or STS with session policies.
- [ ] **Backup alerting**:
  - `backup.sh` only logs failed archiving or base backups; nothing alerts.
  - Add a check, e.g. a control-center job that alerts on the age of `wal-g backup-list` per database, or on `pg_stat_archiver.failed_count`.
  - On ECS, `backup` and `migrate` aren't essential containers, so their failures only show in CloudWatch.
- [ ] **Restore drills**: periodically restore each archive into a scratch pod and compare row counts.
- [ ] **Pre-migration snapshot**: `migrate.sh` doesn't take a base backup before applying migrations; it relies on PITR.
- [ ] **Extension updates** are only reported, never applied.
- [ ] **Postgres major upgrades**: add a pg_upgrade path before moving off 17. `check-postgres-major` only refuses mismatched data.
- [ ] **AWS**:
  - Secrets, now including the backup keys, are plain task env; move them to Secrets Manager.
  - The ALB serves HTTP only, with no TLS.
  - Logs Explorer is empty on Fargate.
- [ ] **DO volume attachment limit** (7 per Droplet; verify): every tenant has db and functions PVCs, which caps tenants per node. Plan node sizing and autoscaling.
- [ ] **Staticbot's own DB backup bucket**: check that it has noncurrent-version expiration. A versioned bucket otherwise keeps everything `wal-g delete` removes.
- [ ] **After a restore**, `pgdata.before-restore-*` (or `/db.before-restore-*` on EFS) has to be deleted by hand.

## 5. Multi-tenant product gaps

- [ ] Supavisor isn't reachable from outside the cluster, so there's no external connection string.
- [ ] No Studio per tenant; its gateway routes answer 503.
- [ ] Logs from all tenants go to one shared Logflare, so there's no per-tenant Logs Explorer.
- [ ] OAuth providers (Google, ...) are enabled only for stacks with a custom domain, never on `{tenant}.sb.*` URLs. Staticbot has to enforce this when it configures Auth.

## 6. Housekeeping

- [ ] After the control-center branch merges, run `python scripts/supabase-sync.py detect`; the shared-module drift should clear. If `volumes/db/jwt.sql` or `webhooks.sql` are still listed, existing databases need a template migration (`_shared/supabase-db-lifecycle/migrations/`).
- [ ] `supabase-sync.py` still reads upstream's deprecated `docker-compose.pg15.yml`. Drop it when upstream removes the file.
