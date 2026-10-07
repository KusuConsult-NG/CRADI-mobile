# `supabase/deploy/`

> **This is the Supabase stack's schema.** On Appwrite the equivalent is
> `infra/appwrite/` — `plan.mjs` declares the collections and
> `provision.mjs` applies them over the REST API. The two are not
> independent: `infra/appwrite/columns.json` is *generated from these
> migrations* by `infra/appwrite/extract-schema.mjs`, so a column added
> here and forgotten there shows up as a diff rather than as a write the
> server rejects later. Keep this the source of truth while both stacks
> exist.

Artifacts for applying the schema to a Supabase project **without the Supabase
CLI** — everything here is meant to be pasted into the dashboard SQL editor.

| File | What it is |
| --- | --- |
| `schema.sql` | **Generated.** All 14 migrations from `supabase/migrations/`, concatenated in filename order, with a banner before each. Paste into *SQL Editor → New query* on an empty project. |
| `build.sh` | Regenerates `schema.sql` from the migrations. |

## Regenerating

`schema.sql` is generated, never hand-edited. After adding or changing a
migration:

```bash
./supabase/deploy/build.sh
git add supabase/deploy/schema.sql
```

The script only reads `supabase/migrations/*.sql` and writes `schema.sql`; it
never touches a database. CI/reviewers can check for drift with:

```bash
./supabase/deploy/build.sh && git diff --exit-code supabase/deploy/schema.sql
```

## Verifying it against a local Postgres

`schema.sql` must produce exactly what applying the migrations one by one
produces. To check (Postgres 15+; no Supabase CLI, no network):

```bash
# A: migrations applied individually
createdb cradi_a
psql -q -v ON_ERROR_STOP=1 -d cradi_a -f supabase/tests/local_stubs.sql
for f in supabase/migrations/*.sql; do
  psql -q -v ON_ERROR_STOP=1 -d cradi_a -f "$f" || break
done

# B: the consolidated file
createdb cradi_b
psql -q -v ON_ERROR_STOP=1 -d cradi_b -f supabase/tests/local_stubs.sql
psql -q -v ON_ERROR_STOP=1 -d cradi_b -f supabase/deploy/schema.sql

# both must report 21
psql -At -d cradi_a -c "select count(*) from information_schema.tables where table_schema='public'"
psql -At -d cradi_b -c "select count(*) from information_schema.tables where table_schema='public'"
```

Then dump and diff `information_schema.tables`/`columns`, `pg_policies`,
`pg_trigger`, `pg_proc`, `pg_indexes`, `pg_constraint`, grants,
`pg_publication_tables` and `storage.buckets` from both databases — they must
be byte-identical. `supabase/tests/rls_smoke.sql` run against either database
must also produce the same output (49 expected `ERROR:` lines).

## `local_stubs.sql` is **local only**

`supabase/tests/local_stubs.sql` fakes the pieces plain Postgres lacks. It is
deliberately **not** part of `schema.sql` and must never be run against a real
Supabase project — it would try to create the `auth` and `storage` schemas that
already exist.

Everything it stubs exists on real Supabase, with one exception:

| Stubbed | On real Supabase |
| --- | --- |
| roles `anon`, `authenticated`, `service_role` | yes |
| `auth.users`, `auth.uid()` | yes (`auth.users` has many more columns; the migrations only use `id`, `email`, `phone`, `raw_user_meta_data`, `email_confirmed_at`, `phone_confirmed_at`) |
| `storage.buckets`, `storage.objects`, `storage.foldername()` | yes (and RLS on `storage.objects` is already enabled, which the stub has to do itself) |
| publication `supabase_realtime` | yes |
| `grant usage on schema public, auth, storage to anon, authenticated` | yes |
| default privileges in `public` for `anon`, `authenticated`, `service_role` | yes |
| **`grant select on auth.users to authenticated`** | **no** — Supabase does not expose `auth.users` to `authenticated`. Nothing in the migrations needs it: every read of `auth.users` is inside a `security definer` function (`public.auth_user_confirmed`, `public.guard_profile_approval`) or a trigger function on `auth.users` itself. The stub only grants it so ad-hoc local queries are convenient. |

`schema.sql` does create two things that need an administrative role, which is
what the dashboard SQL editor gives you (`postgres`):

* triggers on `auth.users` (`on_auth_user_created`, `on_auth_user_updated`);
* policies on `storage.objects` (4 of them).

Both are supported from the Supabase SQL editor.

One harmless local/real difference: `create extension if not exists pgcrypto`
(first line of the init migration) installs pgcrypto **into `public`** on a
plain local Postgres, so a local database shows ~36 extra `public` functions.
On Supabase pgcrypto is already installed in the `extensions` schema, so the
statement is a no-op there. The application's own function count is 37 either
way; the table count (21) is unaffected.
