# Multi-Tenant Supabase — Per-Tenant Template

Deploys one tenant's Supabase into a `tenant-{id}` namespace on the shared DOKS cluster. Intended to be run by Staticbot's tf-runner for each tenant (not wired into the pipeline yet).

Each tenant gets its **own Postgres**. Roles, passwords, extensions, pg_net, pg_cron, Vault and direct database access are therefore isolated per tenant, exactly as on a single-tenant deployment or on Supabase Cloud. Stateless or natively multi-tenant services are shared.

## What Gets Deployed

| Service | Image | Resources (req → limit) |
|---------|-------|-------------------------|
| PostgreSQL | supabase/postgres:17.6.1.136 (+ backup sidecar: continuous WAL archive, daily base backups) | 100m/256Mi → 1/1Gi, PVC `db_storage_size` |
| API gateway (Envoy) | envoyproxy/envoy:v1.39.1 | 20m/64Mi → 300m/256Mi |
| Auth (GoTrue) | supabase/gotrue:v2.196.0 | 30m/64Mi → 200m/256Mi |
| PostgREST | postgrest/postgrest:v14.17 | 30m/64Mi → 200m/256Mi |
| Storage API | supabase/storage-api:v1.74.0 (S3 backend: DO Spaces, `tenants/{id}/` prefix) | 50m/128Mi → 300m/384Mi |
| Meta | supabase/postgres-meta:v0.99.0 | 20m/64Mi → 200m/256Mi |
| Edge Functions | supabase/edge-runtime:v1.76.2 | 40m/128Mi → 500m/512Mi |

Shared (from the shared module, `supabase-shared` namespace): Realtime, Supavisor, ImgProxy, Analytics/Vector and the tenant router.

Plus two jobs (`wait_for_completion = true`):

- **Database migrations** (`migrate-db-<hash>`): brings an existing tenant database up to the current template after a Postgres image bump or a new template migration; a no-op on fresh tenants. See `k8s/db-lifecycle/README.md`.
- **Service registration** upserts the tenant into the shared Realtime and Supavisor through their management APIs (`k8s/register-tenant.py`). It authenticates with an admin JWT signed by `shared_api_jwt_secret` and fails the apply on error. The job name carries a hash of what it registers, so a changed password or JWT secret re-registers the tenant.

## Request Flow

```
https://{id}.{api_domain} → nginx-ingress (wildcard TLS) → tenant router (shared, host → tenant)
  → api-gw.tenant-{id} (Envoy, upstream config) → auth / rest / storage / functions / meta (tenant)
                                                  → realtime (shared; Host rewritten to {id}.realtime…)
```

Envoy is upstream's configuration with two changes: the Realtime cluster points at the shared Realtime, and its Host header rewrite carries the tenant ID, because Realtime takes the tenant from the first label of the Host header.

Direct Postgres access goes through the shared Supavisor as user `postgres.{id}` (session mode on 5432, transaction mode on 6543). It isn't exposed outside the cluster yet.

## Isolation

- A tenant's own database: no shared roles or passwords, and nothing in any tenant's environment can open another tenant's database.
- `tenant-isolation` NetworkPolicy: tenant pods accept traffic only from their own namespace and from the shared namespace.
- The shared namespace restricts its services to their callers (e.g. ImgProxy, which reads every tenant's objects from Spaces, only accepts tenant Storage pods). See the shared module's `k8s-network-policies.tf`.

## Prerequisites

The shared cluster must be deployed first via `staticbot-control-center/infra/digitalocean/modules-tenants/shared/`. This template receives cluster credentials and shared outputs as variables.

## Key Variables

| Variable | Source | Purpose |
|----------|--------|---------|
| `tenant_id` | Migration pipeline | DNS label; namespace `tenant-{id}`, subdomain, Realtime/Supavisor tenant ID |
| `cluster_endpoint`, `cluster_token`, `cluster_ca_certificate` | Shared module outputs | K8s cluster access |
| `shared_api_jwt_secret` | Shared module output | Admin auth for Realtime/Supavisor registration |
| `api_domain` | Shared module output | e.g. `sb.frever.net` |
| `postgres_password` | Generated per tenant | Tenant Postgres (postgres, supabase_admin, service roles) |
| `jwt_secret`, `anon_key`, `service_role_key` | Generated per tenant (or preserved from the source project) | Legacy HS256 keys |
| `supabase_publishable_key`, `supabase_secret_key`, `anon_key_asymmetric`, `service_role_key_asymmetric`, `jwt_keys`, `jwt_jwks` | Generated per tenant (`docker/utils/add-new-auth-keys.sh`) | New API keys (optional) |
| `spaces_*` | Shared Spaces bucket | Storage backend |
| `wal_g_image`, `image_pull_secret_name` | Control-center `docker/wal-g` image; pull secret = registry name (DOCR integration) | WAL-G for backups |
| `backup_s3_*`, `backup_interval_hours`, `backup_retain_full` | Shared backup bucket | WAL archive + base backups under `tenants/{id}/` |

## Files

| File | Purpose |
|------|---------|
| `main.tf` | Provider (standalone — tf-runner runs this directly) and locals |
| `variables.tf` | Tenant config + shared infra references |
| `k8s-namespace.tf` | `tenant-{id}` namespace, Secret, ConfigMaps (init SQL, Envoy, functions), PVCs, NetworkPolicy |
| `k8s-db.tf` | Tenant Postgres (init scripts, persisted `/etc/postgresql-custom`, baseline hook, Postgres major check) and the migrate Job |
| `k8s/db-lifecycle/` | Copy of `_shared/supabase-db-lifecycle`: schema baseline + migrations, backup sidecar, point-in-time restore (see its README; edit the source, not the copy) |
| `k8s-services.tf` | Auth, PostgREST, Storage API, Meta, Edge Functions, Envoy |
| `k8s-provisioning.tf` | Realtime + Supavisor registration job |
| `k8s/register-tenant.py` | Registration script (template-owned, not synced) |
| `outputs.tf` | tenant_id, api_url, keys, db/pooler hosts |
| `docker/` | Subset of upstream `docker/` the Terraform reads; refreshed by `supabase-sync.py` |

## Restoring a tenant database

```bash
NS=tenant-<id>
kubectl -n $NS scale deploy/db --replicas=0
kubectl -n $NS wait --for=delete pod -l app=db --timeout=120s

# Fill in the time just before the incident (UTC), or leave it empty for the latest state
TARGET="2026-06-14 09:30:00+00"
WALG_IMAGE=<wal_g_image>
BUCKET=<backup_s3_bucket> REGION=<backup_s3_region> TENANT=<id>

kubectl -n $NS apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: restore-db
spec:
  restartPolicy: Never
  imagePullSecrets: [{ name: staticbot-prod }]   # the registry's name (DOCR integration)
  initContainers:
    - name: install-wal-g
      image: $WALG_IMAGE
      command: ["cp", "/wal-g", "/walg/wal-g"]
      volumeMounts: [{ name: walg, mountPath: /walg }]
  containers:
    - name: restore
      image: supabase/postgres:17.6.1.136   # the template's current image
      command: ["bash", "/staticbot/restore.sh"]
      env:
        - { name: RECOVERY_TARGET_TIME, value: "$TARGET" }
        - { name: WALG_S3_PREFIX, value: "s3://$BUCKET/tenants/$TENANT" }
        - { name: AWS_REGION, value: "$REGION" }
        - { name: WALG_COMPRESSION_METHOD, value: lz4 }
        # - { name: AWS_ENDPOINT, value: "<backup_s3_endpoint>" }   # non-AWS stores
        # - { name: AWS_S3_FORCE_PATH_STYLE, value: "true" }
        - { name: AWS_ACCESS_KEY_ID, valueFrom: { secretKeyRef: { name: supabase-tenant-config, key: BACKUP_S3_ACCESS_KEY_ID } } }
        - { name: AWS_SECRET_ACCESS_KEY, valueFrom: { secretKeyRef: { name: supabase-tenant-config, key: BACKUP_S3_SECRET_ACCESS_KEY } } }
      volumeMounts:
        - { name: db-data, mountPath: /pvc }
        - { name: db-lifecycle, mountPath: /staticbot, readOnly: true }
        - { name: walg, mountPath: /walg, readOnly: true }
  volumes:
    - { name: db-data, persistentVolumeClaim: { claimName: db-data } }
    - { name: db-lifecycle, configMap: { name: db-lifecycle } }
    - { name: walg, emptyDir: {} }
EOF

kubectl -n $NS logs -f restore-db -c restore    # ends with "restore complete"
kubectl -n $NS delete pod restore-db
kubectl -n $NS scale deploy/db --replicas=1
```

A `RECOVERY_TARGET_TIME` later than the archive's last transaction fails with a message saying how far the archive goes. After the restore the sidecar takes a fresh base backup of the new timeline. Once the tenant checks out, delete `pgdata.before-restore-*` from the volume to reclaim the space.

## Known Gaps

- Not wired into tf-runner yet; nothing provisions tenants today.
- No Studio per tenant (its gateway routes answer 503 behind basic auth).
- Supavisor isn't reachable from outside the cluster yet, so there's no external connection string.
- Logs from all tenants go to one shared Logflare (tagged with `tenant_id`); there's no per-tenant Logs Explorer.

## Upstream Sync

Image versions and the `docker/` subset come from upstream `supabase/supabase` via `scripts/supabase-sync.py`. See the DO single-tenant template's README for the workflow.
