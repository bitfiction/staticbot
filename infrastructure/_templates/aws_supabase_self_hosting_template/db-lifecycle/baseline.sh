#!/bin/bash
# Records this database's schema baseline in _staticbot. Mounted as
# /docker-entrypoint-initdb.d/zz-staticbot-baseline.sh, so it runs once, at
# first boot, right after the image's migrate.sh: everything it records has
# just been applied by the same initdb run.
set -euo pipefail

export PGHOST="${POSTGRES_HOST:-/var/run/postgresql}" PGPORT="${POSTGRES_PORT:-5432}" PGPASSWORD="${POSTGRES_PASSWORD:-}"
export PGUSER=supabase_admin PGDATABASE="${POSTGRES_DB:-postgres}"
initdb=/docker-entrypoint-initdb.d
lifecycle=/staticbot

psql_() { psql -v ON_ERROR_STOP=1 --no-password --no-psqlrc -X -q "$@"; }
sum() { sha256sum "$1" | cut -d' ' -f1; }

psql_ -f "$lifecycle/_schema.sql"

{
  # Image init scripts + migrations, and the upstream SQL mounted next to them
  for dir in init-scripts migrations; do
    for f in "$initdb/$dir"/*.sql; do
      printf 'initdb/%s/%s\t%s\tapplied\tinitdb\n' "$dir" "$(basename "$f")" "$(sum "$f")"
    done
  done
  # Template migrations describe changes this template's init SQL already contains
  for f in "$lifecycle"/[0-9]*.sql; do
    [ -e "$f" ] || continue
    printf 'staticbot/%s\t%s\tapplied\tinitdb\n' "$(basename "$f")" "$(sum "$f")"
  done
} | psql_ -c '\copy _staticbot.migrations (name, checksum, status, applied_by) from pstdin'

psql_ -v image="${STATICBOT_IMAGE:?STATICBOT_IMAGE is required}" <<'SQL'
insert into _staticbot.state (initialized_image, current_image) values (:'image', :'image');
SQL

echo "$0: recorded schema baseline ($(psql_ -Atc 'select count(*) from _staticbot.migrations') files, ${STATICBOT_IMAGE})"
