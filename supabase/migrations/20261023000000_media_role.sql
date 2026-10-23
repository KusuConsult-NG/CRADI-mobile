-- The Media role from the client's permission matrix (4.1).
--
-- Reads validated reports and writes nothing anywhere: no Submit Reports,
-- no Verify, no Validate/Reject, no alerts. It is the only role in the
-- matrix with no write at all, so there is no policy to add — the whole
-- of its access is the report ACL (`reportAcl` in the Appwrite Function),
-- and all this migration does is let the value be stored.
--
-- Appwrite has no CHECK constraint, so this is for the Postgres schema
-- this project migrated from, which is still the schema of record here.
-- Without it a profile set to `media` is refused by the database.
--
-- The constraint is found by its definition rather than by name. It was
-- declared inline on the column, so its name is whatever Postgres chose
-- — `profiles_role_check` on every version this has run against, but a
-- `drop ... if exists` on a guessed name is silently a no-op, and then
-- the old constraint is still there refusing the new value while this
-- migration reports success.
do $$
declare
  existing text;
begin
  for existing in
    select conname
    from pg_constraint
    where conrelid = 'public.profiles'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) like '%ldp_coordinator%'
  loop
    execute format('alter table public.profiles drop constraint %I', existing);
  end loop;
end $$;

alter table public.profiles
  add constraint profiles_role_check check (role in (
    'user', 'ewm', 'ewv', 'ewr', 'ldp_coordinator',
    'project_staff', 'admin', 'techSupport', 'media'));
