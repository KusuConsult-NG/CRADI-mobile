# The migration pipeline

Run against the local stack and a Postgres carrying every migration. The
endpoint, project and key come from the environment for all four scripts; the
spike's `../env.json` is the fallback when they are unset.

    npm install                # pg — three of these scripts need it

    createdb cradi_mig
    psql -d cradi_mig -f supabase/tests/local_stubs.sql
    for f in supabase/migrations/*.sql; do psql -d cradi_mig -v ON_ERROR_STOP=1 -f "$f"; done
    # …seed or restore real data…

    export MIGRATION_PASSWORD=…  # seed-identities sets it, reconcile signs in with it

    node prep.mjs              # collections and attributes
    node seed-identities.mjs   # users, ward teams, role labels — ALWAYS FIRST
    node migrate.mjs           # the three collections that carry the hard parts
    node reconcile.mjs         # exits non-zero if any user's visibility changed

`seed-identities.mjs` runs first because an ACL naming a team, label or user
that does not exist is accepted silently and grants nobody anything.

`reconcile.mjs` compares per-user visibility, not row counts: it queries the
live RLS policy as each user and that user's Appwrite session, and diffs the
ids. It covers **every table a signed-in user can read** — 15 of them — and
fails the run if the schema grows one that is neither reconciled nor listed as
out of scope, because the version that compared `reports` alone still called
its result "100% per-user visibility parity".

    npm test                   # the gate's own tests; needs the Postgres above

Narrow a failure with `RECONCILE_TABLES=profiles,reports`. Add `AW_KEY` for a
per-table total — diagnosis only, never part of a verdict, since a key reads
past the ACLs being compared. `AW_ROWS_API=documents` targets the spike's
pre-1.8 stack; the default is TablesDB, which is what the app uses.

Storage is reported, not compared: nothing here migrates the buckets, so there
is no Supabase-object-name -> Appwrite-file-id mapping to diff.

## Pointing them somewhere else

    AW_ENDPOINT=https://fra.cloud.appwrite.io/v1 \
    AW_PROJECT=… AW_KEY=… MIGRATION_PASSWORD=… node seed-identities.mjs

`AW_ENDPOINT` defaults to `http://localhost:8080/v1`. Every script prints the
endpoint and project it resolved, on stderr, before doing anything — because
the one mistake that costs real time here is a run that looked successful
against the wrong project, and Appwrite answers a misdirected or unpermitted
read with `200 {"total": 0}` rather than an error.

Until recently only `migrate.mjs` read those variables. The other three had
`http://localhost:8080/v1` and `../spike/env.json` baked in — a path that does
not exist in this repository's layout — so they could not be aimed at Cloud at
all, while `docs/CUTOVER-RUNBOOK.md` presented them as the Cloud procedure.

## `MIGRATION_PASSWORD`, and what it does not fix

`seed-identities.mjs` creates every account with this password and
`reconcile.mjs` signs in as every user with it, so the two runs must agree. It
has no default: it used to be the literal `MigratedPassword123` in this file's
sibling, which is acceptable against a throwaway local stack and a disclosed
shared credential for ~650 real accounts the moment the same script is pointed
at Cloud.

It is still a shared password, so it is not a production identity strategy.
**These scripts do not carry Supabase password hashes over**, so every migrated
user's own password stops working whatever you set here. The runbook's Phase 2
covers the two ways out — importing the bcrypt hashes, or a forced reset for
everyone — and which one you pick is a product decision, not a scripting one.
