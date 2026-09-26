# Schema smoke test (plain Postgres, no Supabase CLI needed)

`local_stubs.sql` fakes the Supabase pieces the migration depends on
(`auth.users`, `auth.uid()`, roles, `storage`), so the migration and the
RLS/trigger behaviour can be checked against any Postgres 15+:

```sh
createdb cradi_test
psql -d cradi_test -f supabase/tests/local_stubs.sql
for f in supabase/migrations/*.sql; do psql -d cradi_test -f "$f"; done
psql -d cradi_test -f supabase/tests/rls_smoke.sql   # each "expect ERROR" line should error (35 in total)
```

`categories_e2e.sql` pushes one report per hazard category through the whole
workflow (use a fresh database; it creates its own users):

```sh
psql -d cradi_cats -f supabase/tests/categories_e2e.sql   # expect 9 rows: pending -> verified -> approved
```

`roles_e2e.sql` is the role matrix: one user per role (`user`, `ewm`, `ewv`,
`ewr`, `ldp_coordinator`, `project_staff`, `admin`, `techSupport`) against
every hazard category, driven through submit → peer votes → verified →
decision → reopen, plus the dispute and escalation paths (use a fresh
database; it creates its own users):

```sh
psql -d cradi_roles -f supabase/tests/roles_e2e.sql
```

Expect exactly **39 "ERROR:" lines** (all from statements marked
"expect ERROR") and every cell of the two result matrices to read `PASS`,
with `failures = 0` in the summary.
