# Schema smoke test (plain Postgres, no Supabase CLI needed)

`local_stubs.sql` fakes the Supabase pieces the migration depends on
(`auth.users`, `auth.uid()`, roles, `storage`), so the migration and the
RLS/trigger behaviour can be checked against any Postgres 15+:

```sh
createdb cradi_test
psql -d cradi_test -f supabase/tests/local_stubs.sql
for f in supabase/migrations/*.sql; do psql -d cradi_test -f "$f"; done
psql -d cradi_test -f supabase/tests/rls_smoke.sql   # each "expect ERROR" line should error
```
