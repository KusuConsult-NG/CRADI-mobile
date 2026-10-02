# The migration pipeline

Run against the local stack and a Postgres carrying every migration. Only
the endpoint changes for Cloud.

    createdb cradi_mig
    psql -d cradi_mig -f supabase/tests/local_stubs.sql
    for f in supabase/migrations/*.sql; do psql -d cradi_mig -v ON_ERROR_STOP=1 -f "$f"; done
    # …seed or restore real data…

    node prep.mjs              # collections and attributes
    node seed-identities.mjs   # users, ward teams, role labels — ALWAYS FIRST
    AW_PROJECT=… AW_KEY=… node migrate.mjs
    node reconcile.mjs         # exits non-zero if any user's visibility changed

`seed-identities.mjs` runs first because an ACL naming a team, label or user
that does not exist is accepted silently and grants nobody anything.

`reconcile.mjs` compares per-user visibility, not row counts: it queries the
live RLS policy as each user and that user's Appwrite session, and diffs.
Verified to fail — granting one ward's team read on another ward's report
makes it exit 1.
