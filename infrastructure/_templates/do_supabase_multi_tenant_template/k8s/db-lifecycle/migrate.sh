#!/bin/bash
# Brings an existing tenant database up to the current template:
#   1. Supabase image migrations the database hasn't seen (newer image), each
#      applied or skipped per image-migrations.txt. An image migration without
#      a decision fails the job before anything is applied.
#   2. Template migrations (k8s/db-lifecycle/migrations) not yet applied.
#   3. Reports what it can't fix: upstream init SQL that changed since the
#      database was created, and extensions behind the image's version.
# Runs as a Job with the database's current image, so the image's migration
# files are at /docker-entrypoint-initdb.d/migrations.
set -euo pipefail

export PGUSER=supabase_admin PGDATABASE="${PGDATABASE:-postgres}"
: "${PGHOST:?}" "${PGPASSWORD:?}" "${STATICBOT_IMAGE:?}"
image_migrations=/docker-entrypoint-initdb.d/migrations
lifecycle=/staticbot

psql_() { psql -v ON_ERROR_STOP=1 --no-password --no-psqlrc -X -q "$@"; }
sum() { sha256sum "$1" | cut -d' ' -f1; }
record() { # name checksum status note
  psql_ -v name="$1" -v checksum="$2" -v status="$3" -v note="$4" <<'SQL'
insert into _staticbot.migrations (name, checksum, status, note, applied_by)
values (:'name', :'checksum', :'status', nullif(:'note', ''), 'migrate-job');
SQL
}
decision() { # file → "apply" | "skip" | ""
  awk -v f="$1" '!/^[[:space:]]*(#|$)/ && $1 == f { print $2; exit }' "$lifecycle/image-migrations.txt"
}
reason() { # file → text after the decision
  awk -v f="$1" '!/^[[:space:]]*(#|$)/ && $1 == f { $1 = ""; $2 = ""; sub(/^[[:space:]]+/, ""); print; exit }' "$lifecycle/image-migrations.txt"
}

for i in $(seq 1 60); do
  pg_isready -q && break
  [ "$i" = 60 ] && { echo "ERROR: database at $PGHOST not ready" >&2; exit 1; }
  sleep 5
done

if [ "$(psql_ -Atc "select to_regclass('_staticbot.state') is not null")" != t ]; then
  echo "ERROR: no _staticbot baseline. This database wasn't initialised by this template, so" >&2
  echo "       there's no record of which migrations it has; refusing to guess." >&2
  exit 1
fi
psql_ -f "$lifecycle/_schema.sql"
done_names=$(psql_ -Atc "select name from _staticbot.migrations")
is_done() { grep -qxF "$1" <<<"$done_names"; }

# 1. Image migrations
pending=() undecided=()
for f in "$image_migrations"/*.sql; do
  n=$(basename "$f")
  is_done "initdb/migrations/$n" || is_done "image/$n" && continue
  pending+=("$f")
  [ -n "$(decision "$n")" ] || undecided+=("$n")
done
if [ ${#undecided[@]} -gt 0 ]; then
  echo "ERROR: ${STATICBOT_IMAGE} adds image migrations without a decision in image-migrations.txt:" >&2
  printf '  %s\n' "${undecided[@]}" >&2
  echo "Review each one (some are only meant for new databases) and add 'apply' or 'skip <reason>'." >&2
  exit 1
fi
for f in "${pending[@]+"${pending[@]}"}"; do
  n=$(basename "$f")
  if [ "$(decision "$n")" = apply ]; then
    echo "applying image/$n"
    psql_ -f "$f"
    record "image/$n" "$(sum "$f")" applied ""
  else
    echo "skipping image/$n: $(reason "$n")"
    record "image/$n" "$(sum "$f")" skipped "$(reason "$n")"
  fi
done

# 2. Template migrations, in name order
for f in "$lifecycle"/[0-9]*.sql; do
  [ -e "$f" ] || continue
  n=$(basename "$f")
  is_done "staticbot/$n" && continue
  echo "applying staticbot/$n"
  psql_ -f "$f"
  record "staticbot/$n" "$(sum "$f")" applied ""
done

# 3. Reports
while read -r key path; do
  [ -n "$key" ] || continue
  recorded=$(psql_ -v name="initdb/$path" -At <<<"select checksum from _staticbot.migrations where name = :'name'")
  if [ -n "$recorded" ] && [ "$recorded" != "$(sum "/initsql/$key")" ]; then
    echo "NOTE: upstream $key changed since this database was initialised; make sure a template migration covers it"
  fi
done < "$lifecycle/init-mounts.txt"
psql_ -At -F' ' -c "select 'NOTE: extension ' || name || ' ' || installed_version || ' is behind ' || default_version || ' (not updated automatically)' from pg_available_extensions where installed_version is not null and installed_version <> default_version order by name"

psql_ -v image="$STATICBOT_IMAGE" <<'SQL'
update _staticbot.state set current_image = :'image', migrated_at = now();
SQL
echo "database is up to date with ${STATICBOT_IMAGE}"
