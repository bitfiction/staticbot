-- Staticbot's record of how this database's schema was built and upgraded.
-- Owned by supabase_admin. Tenants (postgres) can read it through
-- pg_read_all_data, which Supabase grants them, but can't change it.
-- Idempotent; run by baseline.sh at first boot and by migrate.sh.
set client_min_messages = warning;

create schema if not exists _staticbot;
revoke all on schema _staticbot from public;

-- One row per SQL file that shaped the schema:
--   initdb/<dir>/<file>  ran at first boot (image + upstream docker/volumes/db SQL)
--   image/<file>         Supabase image migration applied or skipped later
--   staticbot/<file>     template-owned migration (k8s/db-lifecycle/migrations)
create table if not exists _staticbot.migrations (
  name       text primary key,
  checksum   text not null,
  status     text not null check (status in ('applied', 'skipped')),
  note       text,
  applied_by text not null,
  applied_at timestamptz not null default now()
);

create table if not exists _staticbot.state (
  singleton         boolean primary key default true check (singleton),
  initialized_image text not null,
  initialized_at    timestamptz not null default now(),
  current_image     text not null,
  migrated_at       timestamptz
);
