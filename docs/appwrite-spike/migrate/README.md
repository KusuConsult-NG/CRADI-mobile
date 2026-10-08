# The migration pipeline

Run against the local stack and a Postgres carrying every migration. The
endpoint, project and key come from the environment for all five scripts; the
spike's `../env.json` is the fallback when they are unset.

    npm install                # pg — four of these scripts need it

    createdb cradi_mig
    psql -d cradi_mig -f supabase/tests/local_stubs.sql
    for f in supabase/migrations/*.sql; do psql -d cradi_mig -v ON_ERROR_STOP=1 -f "$f"; done
    psql -d cradi_mig -f supabase/tests/migration_fixture.sql   # or restore real data

    # Schema and first contact, from the repo root — not scripts in here:
    node infra/appwrite/provision.mjs
    node infra/appwrite/phase0.mjs      # preflight + verify + behaviour probes

    node seed-identities.mjs   # users, ward teams, role labels — ALWAYS FIRST
    node copy-tables.mjs       # all nine collections, in dependency order
    SUPABASE_URL=… node copy-storage.mjs   # the buckets, and the URLs on rows
    node reconcile.mjs         # exits non-zero if any user's visibility changed

`seed-identities.mjs` runs first because an ACL naming a team, label or user
that does not exist is accepted silently and grants nobody anything. It assigns
labels through `accountLabels` from `functions/cradi/src/lib/policy.js` — the
same rule `write.js` applies at runtime, so a migrated account starts with
exactly what a later profile edit would give it.

`copy-tables.mjs` handles all nine collections, in dependency order — a
report's ACL names its author's ward team and a verification's names the
report's, so `profiles` is read before `reports` before `verifications`.

It is schema-driven from **`plan.mjs`'s `COLLECTIONS`**, not `columns.json`:
that file is derived from the migrations alone, and the plan adds the
denormalised columns Appwrite needs and Postgres never had
(`verifications.state`, `reports.userName`). The camelCase rule comes from
`extract-schema.mjs`'s own `toField`, and the Appwrite-only values from the same
expressions `write.js` uses. A Postgres column with no planned column is
reported, not dropped in silence.

The ACLs for the six come from `policy.js`'s `RULES`, so a migrated row carries
what the `client` Function stamps on one created afterwards. The three with row
security on use `migrate.mjs`'s builders instead, which reproduce the RLS. Those
two sets differ — see `ACL_SOURCE` in `copy-tables.mjs` for which roles and why
narrowing access mid-cutover is not this script's call.

`reconcile.mjs` compares per-user visibility, not row counts: it queries the
live RLS policy as each user and that user's Appwrite session, and diffs the
ids. It covers **every table a signed-in user can read** — 15 of them — and
fails the run if the schema grows one that is neither reconciled nor listed as
out of scope, because the version that compared `reports` alone still called
its result "100% per-user visibility parity".

A table that refuses the session (401/403) is reported under its own `denied`
column, never as an empty read. The two are only the same when the table has
rows: seven of the fifteen are empty at cutover, and for those a 401 read as
"sees nothing" matches Postgres's zero rows exactly — a table nobody could open
passing as clean until the day it filled up. Rows `copy-tables.mjs` declines are
forgiven by name through `NOT_COPIED`, which keeps them in the diff with their
ids and reasons rather than filtering them out of the query; a filter would make
the gate unable to tell a declared skip from a row that failed to migrate.

    npm test                   # needs the Postgres above

Narrow a failure with `RECONCILE_TABLES=profiles,reports`. Add `AW_KEY` for a
per-table total — diagnosis only, never part of a verdict, since a key reads
past the ACLs being compared. `AW_ROWS_API=documents` targets the spike's
pre-1.8 stack; the default is TablesDB, which is what the app uses.

The suites: `storage-ids.test.mjs` (pure), `copy-tables.test.mjs`,
`reconcile.test.mjs` (the copiers and the gate against a real Postgres and an
Appwrite stand-in that evaluates the permission strings `migrate.mjs` actually
stamps), and `seed-identities.test.mjs` (which endpoint each account goes to,
and what a re-run does to a password).

They run in CI, in the `Appwrite Migration Pipeline (Node) Test` job, against a
`postgres:16` service container built the same way as above. They did not, and
that is why the shared-password seeder reached the production project: the
change to import the bcrypt hashes was never committed, nothing failed, and no
job ran the suite that would have noticed.

`supabase/tests/migration_fixture.sql` is the fixture, and it is not
decoration — every suite here **skips** a test whose fixture row is absent, so
a fixture that stopped carrying one branch would turn those tests into silent
no-ops. The CI job asserts the branches are present before running anything,
and several counts in the suites are pinned to it (two orphan reports, one
non-bcrypt hash). Read the header of that file before changing it.

`migrate.mjs` no longer copies anything: it is the ACL and identity module that
`copy-tables.mjs` and `seed-identities.mjs` import. `prep.mjs` is gone with it —
it created the spike's own snake_case collections, which nothing writes to now,
so running it would have provisioned a second wrong schema beside the real one.
`infra/appwrite/provision.mjs` is the provisioner, and `verify.mjs` checks it.

`copy-storage.mjs` copies both buckets and then rewrites the Supabase URLs
still sitting on migrated rows. The file id is **not** the migration's to
choose: the Flutter client derives it from the storage path at render time and
nothing persists it, so a file under any other id is unreachable and the only
symptom is an image that does not load. `storage-ids.mjs` is a port of
`AppwriteDataBackend.fileIdFor`, pinned by `storage-ids.test.mjs` against the
cases the Dart suite asserts. Two paths colliding on one id stops the run,
because the second upload would replace the first user's evidence.

It needs `SUPABASE_URL` to read the bytes (both buckets are public;
`SUPABASE_SERVICE_ROLE_KEY` is only for one that is not). `STORAGE_MAP=path`
writes the path -> id mapping as JSON.

The gate compares storage by **presence**: every Supabase object must be in
Appwrite under the id the app will ask for. Not per-user — both systems serve
these buckets to everyone, so a per-user diff would be the same answer six
times.

## Pointing them somewhere else

    AW_ENDPOINT=https://fra.cloud.appwrite.io/v1 \
    AW_PROJECT=… AW_KEY=… node seed-identities.mjs

`AW_ENDPOINT` defaults to `http://localhost:8080/v1`. Every script prints the
endpoint and project it resolved, on stderr, before doing anything — because
the one mistake that costs real time here is a run that looked successful
against the wrong project, and Appwrite answers a misdirected or unpermitted
read with `200 {"total": 0}` rather than an error.

Until recently only `migrate.mjs` read those variables. The other three had
`http://localhost:8080/v1` and `../spike/env.json` baked in — a path that does
not exist in this repository's layout — so they could not be aimed at Cloud at
all, while `docs/CUTOVER-RUNBOOK.md` presented them as the Cloud procedure.

## Passwords

Nothing here knows anybody's password, and there is no `MIGRATION_PASSWORD` any
more. `seed-identities.mjs` imports each account's own bcrypt hash from
`auth.users.encrypted_password` via `POST /users/bcrypt`, so every user keeps
the password they have; an account with no hash — OAuth-only, magic-link-only —
is created without one, which is what it had. A hash in some other format is
counted and named in `failures`, never dropped in silence.

`reconcile.mjs` therefore cannot sign in, and does not try: it mints a session
with `POST /users/{userId}/tokens` + `POST /account/sessions/token`, which is
what `AW_KEY` is for there. Every row it reads still goes through that user's
own session — a key-based read would bypass the ACLs that are the whole subject
of the comparison.

**The one step that does not converge on a re-run.** Appwrite takes a hash only
at creation; `PATCH /users/{userId}/password` accepts a plaintext and no
endpoint sets a pre-existing hash on an existing account. So an account that is
already there gets a 409 and keeps whatever password created it. The seeder
counts those under `passwords.alreadyExisted` and names each one, and the
runbook's 5.1 has the delete-and-re-create procedure for a project already
seeded with a shared password. Everything else here is safe to re-run.

It got this way late: the earlier seeder created every account with one shared
password and the earlier gate signed in with it, which is acceptable against a
throwaway local stack and a disclosed shared credential for ~650 real accounts
the moment the same script is pointed at Cloud. `seed-identities.test.mjs`
exists because that version ran against the production project — nothing failed,
nothing was red, and the summary line read "users created" either way.
