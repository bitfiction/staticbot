# Template migrations

SQL here brings databases created by an older template version up to what the
current first boot produces. Add one when a sync changes
upstream's `docker/volumes/db/*.sql` (those files only run at first boot) or
when the template's own init changes.

- Name: `<UTC timestamp>_<description>.sql`, e.g. `20261012120000_grant_functions_admin_extensions.sql`.
- Make it idempotent: databases created after it was added record it as applied without running it, and a failed job may re-run it.
- Never edit one that has shipped; add a new one.

`migrate.sh` applies pending files in name order as `supabase_admin` and records them in `_staticbot.migrations`.
