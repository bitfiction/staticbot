#!/bin/bash
# Backup sidecar for the tenant Postgres, following Staticbot's own database
# (infra/digitalocean/modules/postgres-droplet): Postgres archives every WAL
# segment with WAL-G (archive_command, archive_timeout=60); this loop takes a
# base backup every BACKUP_INTERVAL_HOURS and keeps BACKUP_RETAIN_FULL of them.
# It also stores the pgsodium/Vault root key next to the archive, because it
# lives outside PGDATA and a restore without it can't decrypt Vault secrets.
#
# Runs in the db pod with the same PGDATA mount, so `wal-g backup-push` sees the
# data directory Postgres reports. Not `set -e`: one failed backup must not stop
# the loop.
set -uo pipefail

walg=/walg/wal-g
pgdata=/var/lib/postgresql/data
state=/var/lib/postgresql/backup-state
interval=$(( ${BACKUP_INTERVAL_HOURS:-24} * 3600 ))
retain=${BACKUP_RETAIN_FULL:-14}
export PGHOST=127.0.0.1 PGPORT="${PGPORT:-5432}" PGUSER=supabase_admin PGDATABASE=postgres

log() { echo "[$(date -u +%FT%TZ)] $*"; }

# First boot initialises over the Unix socket only; wait for the real server.
until pg_isready -q; do sleep 5; done
log "database is up; base backup every ${BACKUP_INTERVAL_HOURS:-24}h, keeping ${retain}"

backup_key() {
  local key=/etc/postgresql-custom/pgsodium_root.key listing
  [ -f "$state/pgsodium_root.key.stored" ] && return 0
  [ -f "$key" ] || { log "WARN: $key not created yet"; return 1; }
  listing=$("$walg" st ls 2>/dev/null) || { log "WARN: can't list the archive; retrying later"; return 1; }
  if awk '{ print $NF }' <<<"$listing" | grep -qxF pgsodium_root.key; then
    # Never overwrite (st put doesn't refuse on its own): a different key in
    # the archive means this volume's key isn't the one the backups' Vault
    # secrets were encrypted with.
    if "$walg" st get pgsodium_root.key /tmp/stored.key && cmp -s /tmp/stored.key "$key"; then
      touch "$state/pgsodium_root.key.stored"; log "pgsodium root key already stored"
    else
      log "ERROR: the archive holds a different pgsodium root key than this database; not overwriting it"
    fi
    rm -f /tmp/stored.key
  # --no-compress keeps the object name exact, so restore.sh can `st get` it
  elif "$walg" st put --no-compress "$key" pgsodium_root.key; then
    touch "$state/pgsodium_root.key.stored"; log "stored pgsodium root key"
  fi
}

archived_failures=0
while true; do
  backup_key

  last=$(cat "$state/last_base_backup" 2>/dev/null || echo 0)
  if [ $(( $(date +%s) - last )) -ge "$interval" ]; then
    log "base backup starting"
    if "$walg" backup-push "$pgdata"; then
      date +%s > "$state/last_base_backup"
      "$walg" delete retain FULL "$retain" --confirm || log "WARN: retention cleanup failed"
      log "base backup complete"
    else
      log "ERROR: base backup failed; retrying in 5 minutes"
    fi
  fi

  # A failing archive_command keeps WAL in pg_wal until the volume fills up.
  failed=$(psql -XAtc "select failed_count from pg_stat_archiver" 2>/dev/null || echo "$archived_failures")
  if [ "$failed" -gt "$archived_failures" ]; then
    log "ERROR: WAL archiving failed $(( failed - archived_failures )) time(s): $(psql -XAtc "select last_failed_wal || ' at ' || last_failed_time from pg_stat_archiver")"
    archived_failures=$failed
  fi

  sleep 300
done
