# Tenant database lifecycle

Schema upgrades and backups for a tenant's own Postgres.

## Schema upgrades

A Supabase database gets its Postgres-level schema (roles, grants, event triggers, extensions) from SQL that runs **only at first boot**: the image's own `init-scripts/` and `migrations/`, plus upstream's `docker/volumes/db/*.sql`. Upstream doesn't apply later changes to existing databases (its `update.sh` only lists manual steps). This directory is how the template does.

GoTrue, Storage and Realtime migrate their own schemas on start; this only covers the Postgres-level SQL.

## What runs when

| When | What | Script |
|------|------|--------|
| First boot | Records the baseline in `_staticbot`: the image, every init file that ran (with checksums), and the template migrations that already existed | `baseline.sh` (mounted as `/docker-entrypoint-initdb.d/zz-staticbot-baseline.sh`, so it runs right after the image's `migrate.sh`) |
| Every apply where the image or these files changed | `migrate-db-<hash>` Job: applies pending image migrations per `image-migrations.txt`, then pending template migrations; reports drift; fails the apply on error | `migrate.sh` |
| Every pod start | `check-postgres-major` init container stops the pod with a clear message if the data directory's Postgres major doesn't match the image's | `k8s-db.tf` |

On a fresh tenant the Job finds everything recorded and does nothing. A database without a `_staticbot` baseline is refused rather than guessed at.

## Files

| File | Purpose |
|------|---------|
| `_schema.sql` | `_staticbot.migrations` and `_staticbot.state` (owned by supabase_admin; tenants can read but not write) |
| `baseline.sh` | First-boot baseline |
| `migrate.sh` | The migrate Job |
| `image-migrations.txt` | `apply` / `skip <reason>` per Supabase image migration, for existing databases |
| `migrations/*.sql` | Template migrations (see `migrations/README.md`) |
| `backup.sh` | Backup sidecar (see below) |
| `restore.sh` | Point-in-time restore (see below) |

## When syncing upstream

`python scripts/supabase-sync.py detect` lists both kinds of work:

- **Postgres image bump**: new image migrations without a decision. Read each one. Upstream writes some only for new databases (`20260421000000_pg_graphql-off-by-default.sql` drops pg_graphql); `skip` those with a reason, `apply` the rest. The Job refuses to run until every pending one has a decision.
- **`docker/volumes/db/*.sql` changed**: write an idempotent template migration that makes an existing database match the new first-boot result.

## Inspecting a tenant

```sql
select * from _staticbot.state;
select name, status, note, applied_by, applied_at from _staticbot.migrations
 where applied_by = 'migrate-job' order by applied_at;
```

The Job's log also lists extensions behind the image's version and upstream init SQL that changed since the database was created.

## Backups

Modeled on Staticbot's own database (`staticbot-control-center/infra/digitalocean/modules/postgres-droplet`), the setup we recovered from in June:

- **Continuous WAL archiving**: Postgres runs `archive_command = wal-g wal-push`, `archive_timeout = 60`, so at most about a minute of transactions is at risk if the volume is lost.
- **Base backups**: the `backup` sidecar in the db pod runs `wal-g backup-push` every `backup_interval_hours` (24) and `wal-g delete retain FULL <backup_retain_full>` (14), so you can restore to any point in the last ~14 days.
- **Vault root key**: `pgsodium_root.key` lives in `/etc/postgresql-custom`, not PGDATA, so the sidecar stores it once next to the archive (`pgsodium_root.key`). It never overwrites a different stored key; it logs an error instead.
- **Archive health**: the sidecar logs an error whenever `pg_stat_archiver.failed_count` grows. A failing archive keeps WAL in `pg_wal` until the volume fills.

Everything lives under `s3://<backup_s3_bucket>/tenants/<tenant_id>/`. WAL-G comes from the `wal_g_image` tool image (a static build; WAL-G's releases are glibc and the Postgres image is Alpine), copied in by the `install-wal-g` init container.

Logs: `kubectl -n tenant-<id> logs deploy/db -c backup`.

## Restoring a tenant

`restore.sh` fetches a base backup into the db volume, replays archived WAL up to `RECOVERY_TARGET_TIME` (or to the end of the archive), promotes, and stops. The previous data directory is kept as `pgdata.before-restore-<timestamp>`, and the Vault key is fetched from the archive if the volume doesn't have it (e.g. a new, empty volume).

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

## Not covered yet

- **Pre-migration snapshot**: the migrate Job doesn't take a base backup first. With continuous archiving you can still restore to just before it ran.
- **Extension updates**: reported, never applied (`ALTER EXTENSION ... UPDATE` needs per-extension review).
- **Postgres major upgrades**: tenants start on 17; a future major (18) needs a pg_upgrade step first. The init container only prevents starting on mismatched data.
- **DO single-tenant, AWS and the shared metadata database** don't have this yet.
