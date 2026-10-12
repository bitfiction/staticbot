# Supabase database lifecycle

Schema upgrades and backups for a Supabase Postgres (`supabase/postgres:17`), shared by every Staticbot Supabase template.

**Source:** `staticbot/infrastructure/_templates/_shared/supabase-db-lifecycle`. `scripts/supabase-sync.py apply --safe` copies it into each template (`k8s/db-lifecycle/` in the Kubernetes templates, `db-lifecycle/` in AWS and the multi-tenant shared module), and `detect` flags copies that drifted. Edit the source, never a copy.

## Schema upgrades

A Supabase database gets its Postgres-level schema (roles, grants, event triggers, extensions) from SQL that runs **only at first boot**: the image's own `init-scripts/` and `migrations/`, plus upstream's `docker/volumes/db/*.sql`. Upstream doesn't apply later changes to existing databases (its `update.sh` only lists manual steps).

GoTrue, Storage and Realtime migrate their own schemas on start; this only covers the Postgres-level SQL.

| When | What | Script |
|------|------|--------|
| First boot | Records the baseline in `_staticbot`: the image, every init file that ran (with checksums), and the template migrations that already existed | `baseline.sh`, mounted as `/docker-entrypoint-initdb.d/zz-staticbot-baseline.sh` so it runs right after the image's `migrate.sh` |
| After an image or template change | Applies pending image migrations per `image-migrations.txt`, then pending template migrations; reports drift | `migrate.sh` (a Job on Kubernetes, a one-shot container on ECS) |
| Every start | Refuses a data directory from another Postgres major | the template's `check-postgres-major` step |

On a fresh database `migrate.sh` finds everything recorded and does nothing. A database without a `_staticbot` baseline is refused rather than guessed at.

### When syncing upstream

`python scripts/supabase-sync.py detect` lists both kinds of work:

- **Postgres image bump**: new image migrations without a decision. Read each one. Upstream writes some only for new databases (`20260421000000_pg_graphql-off-by-default.sql` drops pg_graphql); `skip` those with a reason, `apply` the rest. `migrate.sh` refuses to run until every pending one has a decision.
- **`docker/volumes/db/*.sql` changed**: write an idempotent template migration in `migrations/` that makes an existing database match the new first-boot result.

### Inspecting a database

```sql
select * from _staticbot.state;
select name, status, note, applied_by, applied_at from _staticbot.migrations
 where applied_by = 'migrate-job' order by applied_at;
```

## Backups

Modeled on Staticbot's own database (`staticbot-control-center/infra/digitalocean/modules/postgres-droplet`), the setup we recovered from in June:

- **Continuous WAL archiving**: Postgres runs `archive_command = wal-g wal-push`, `archive_timeout = 60`, so at most about a minute of transactions is at risk if the volume is lost.
- **Base backups**: `backup.sh` runs next to Postgres, does `wal-g backup-push` every `BACKUP_INTERVAL_HOURS` (24) and `wal-g delete retain FULL $BACKUP_RETAIN_FULL` (14).
- **Vault root key**: `pgsodium_root.key` lives in `/etc/postgresql-custom`, not PGDATA, so `backup.sh` stores it once next to the archive. It never overwrites a different stored key; it logs an error instead.
- **Archive health**: `backup.sh` logs an error whenever `pg_stat_archiver.failed_count` grows. A failing archive keeps WAL in `pg_wal` until the volume fills.

WAL-G comes from the static build in `staticbot-control-center/docker/wal-g` (WAL-G's releases are glibc builds; the Postgres image is Alpine). Templates copy `/wal-g` from that image into a shared volume.

## Restoring

`restore.sh` fetches a base backup into the stopped database's volume, replays archived WAL up to `RECOVERY_TARGET_TIME` (or to the end of the archive), promotes and stops. The previous data directory is kept as `<data>.before-restore-<timestamp>`, and the Vault key is fetched from the archive when the volume doesn't have it (e.g. a new, empty volume). A target later than the archive's last transaction fails with a message saying how far the archive goes. Afterwards `backup.sh` takes a fresh base backup of the new timeline.

How to run it (stop the database, run `restore.sh`, start it again) is in each template's README.

## Not covered yet

- **Pre-migration snapshot**: `migrate.sh` doesn't take a base backup first; with continuous archiving you can still restore to just before it ran.
- **Extension updates**: reported, never applied (`ALTER EXTENSION ... UPDATE` needs per-extension review).
- **Postgres major upgrades**: databases start on 17; a future major needs a pg_upgrade step first.
