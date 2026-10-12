#!/bin/bash
# Point-in-time restore of a Supabase database from its WAL-G archive.
# Run it once, with the database stopped (see your template's README):
#   - the database volume mounted at /pvc (the whole volume, not the data
#     subdirectory); its layout is set by DATA_SUBDIR (default pgdata),
#     CUSTOM_SUBDIR (postgresql-custom) and STATE_SUBDIR (backup-state)
#   - WAL-G at /walg/wal-g and the WALG_* / AWS_* env the database uses
#   - RECOVERY_TARGET_TIME (e.g. "2026-06-14 09:30:00+00") or empty for the
#     latest state; BACKUP_NAME (default LATEST) to pick a base backup
# The current data directory is kept as <DATA_SUBDIR>.before-restore-<timestamp>.
# Recovery runs here and promotes, so the database afterwards starts normally.
set -euo pipefail

walg=/walg/wal-g
pvc=/pvc
data="$pvc/${DATA_SUBDIR:-pgdata}"
custom="$pvc/${CUSTOM_SUBDIR:-postgresql-custom}"
state="$pvc/${STATE_SUBDIR:-backup-state}"
backup=${BACKUP_NAME:-LATEST}
target=${RECOVERY_TARGET_TIME:-}
stamp=$(date -u +%Y%m%dT%H%M%SZ)
log() { echo "[$(date -u +%FT%TZ)] $*"; }

"$walg" backup-list

if [ -d "$data" ] && [ -n "$(ls -A "$data")" ]; then
  mv "$data" "$data.before-restore-$stamp"
  log "kept the current data directory as $(basename "$data").before-restore-$stamp"
fi
mkdir -p "$data" "$custom"
chown postgres:postgres "$data" && chmod 700 "$data"

log "fetching base backup $backup"
gosu postgres "$walg" backup-fetch "$data" "$backup"

# Vault secrets need the root key they were encrypted with
if [ ! -f "$custom/pgsodium_root.key" ]; then
  "$walg" st get pgsodium_root.key "$custom/pgsodium_root.key"
  chown postgres:postgres "$custom/pgsodium_root.key"
  log "restored the pgsodium root key from the archive"
fi
install -o postgres -g postgres -m 600 "$custom/pgsodium_root.key" /etc/postgresql-custom/pgsodium_root.key

touch "$data/recovery.signal"
# Archive during recovery too: promotion starts a new timeline, and its history
# file must reach the archive or a later restore can't follow it.
# The image's postgresql.conf pins data_directory to /var/lib/postgresql/data.
args=(-c config_file=/etc/postgresql/postgresql.conf -c "data_directory=$data" -c listen_addresses=
      -c "restore_command=$walg wal-fetch %f %p" -c recovery_target_action=promote
      -c archive_mode=on -c "archive_command=$walg wal-push %p")
[ -n "$target" ] && args+=(-c "recovery_target_time=$target")

log "replaying WAL ${target:+up to $target}"
recovery_log="$pvc/restore-$stamp.log"
# pg_ctl writes it as postgres, and the volume root is usually root's
install -o postgres -g postgres -m 600 /dev/null "$recovery_log"
gosu postgres pg_ctl -D "$data" -w -t 3600 -l "$recovery_log" -o "${args[*]@Q}" start || true
# Postgres deletes recovery.signal when it promotes; if it stops instead, say why.
while [ -e "$data/recovery.signal" ]; do
  if ! gosu postgres pg_ctl -D "$data" status >/dev/null; then
    log "ERROR: recovery stopped before promotion; end of $recovery_log:"
    tail -6 "$recovery_log" >&2
    if grep -q 'recovery ended before configured recovery target was reached' "$recovery_log"; then
      log "The archive ends before RECOVERY_TARGET_TIME ($(grep -o 'last completed transaction was at log time .*' "$recovery_log" | tail -1)). Pick an earlier time, or leave it empty to restore everything archived."
    fi
    exit 1
  fi
  sleep 2
done
log "promoted; $(grep -o 'last completed transaction was at log time .*' "$recovery_log" | tail -1)"
gosu postgres pg_ctl -D "$data" -w -m fast stop

# The backup sidecar takes a base backup of the new timeline on its next start
rm -f "$state/last_base_backup"
log "restore complete; start the database again"
