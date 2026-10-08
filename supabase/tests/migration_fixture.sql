-- Fixture for the Appwrite migration suite (`docs/appwrite-spike/migrate`).
--
-- Apply after `local_stubs.sql` and every file in `supabase/migrations/`. The
-- suite reads these rows through the real RLS policies as each real user, so
-- the fixture is not decoration: it has to carry one account per branch the
-- policies and the migration scripts actually take, and several assertions are
-- pinned to the counts below.
--
--   * six profiles spanning `app_role()`'s branches, including an admin that
--     Postgres demotes to 'user' because it is not approved — the privilege
--     escalation the reconciliation gate exists to catch;
--   * two `ewm` monitors in DIFFERENT wards, so a ward-team ACL that is too
--     broad shows up as one monitor reading the other's ward;
--   * one bcrypt hash per supported prefix ($2a$, $2b$, $2y$), one hash in
--     another format, and one account with none — the three branches in
--     `seed-identities.mjs`;
--   * two orphan reports with no LGA and two verifications on them, which
--     `copy-tables.mjs` declines and `reconcile.mjs`'s NOT_COPIED forgives by
--     name. Production carries four of the former; two is enough to prove the
--     classification, and the suite asserts exactly two.
--
-- The hashes are not real passwords. They are the shape `POST /users/bcrypt`
-- accepts, which is all the suite inspects: it asserts the hash crosses to
-- Appwrite unchanged, never that it verifies against anything.

-- Accounts only: a trigger creates the matching `public.profiles` row, and
-- `guard_profile_approval` refuses to approve an account whose email is not
-- confirmed, so `email_confirmed_at` is set here rather than left null.
insert into auth.users (id, email, email_confirmed_at, encrypted_password) values
  ('00000000-0000-0000-0000-00000000a001','citizen@example.ng', now(),
   '$2a$10$abcdefghijklmnopqrstuv0123456789ABCDEFGHIJKLMNOPQRST'),
  ('00000000-0000-0000-0000-00000000a002','ewm.northbank@example.ng', now(),
   '$2b$12$bcdefghijklmnopqrstuvw0123456789ABCDEFGHIJKLMNOPQRST'),
  ('00000000-0000-0000-0000-00000000a003','ewm.wadata@example.ng', now(),
   '$2y$10$cdefghijklmnopqrstuvwx0123456789ABCDEFGHIJKLMNOPQRST'),
  ('00000000-0000-0000-0000-00000000a004','admin@example.ng', now(),
   '$2a$10$defghijklmnopqrstuvwxy0123456789ABCDEFGHIJKLMNOPQRST'),
  -- Not bcrypt. The seeder must create the account anyway, count it, and name
  -- it: that user has lost their password and nobody would otherwise notice.
  ('00000000-0000-0000-0000-00000000a005','ewv@example.ng', now(),
   '$argon2id$v=19$m=65536,t=3,p=4$abc$def'),
  -- No hash at all, as an OAuth-only or magic-link-only account has.
  ('00000000-0000-0000-0000-00000000a006','unapproved.admin@example.ng', now(), null)
on conflict (id) do nothing;

update public.profiles set name = v.name, role = v.role, state = v.state,
       lga = v.lga, ward = v.ward, is_approved = v.appr, is_disabled = v.dis
from (values
  ('00000000-0000-0000-0000-00000000a001'::uuid,'Citizen','user','Benue','Makurdi','North Bank I', true, false),
  ('00000000-0000-0000-0000-00000000a002','Monitor North','ewm','Benue','Makurdi','North Bank I', true, false),
  ('00000000-0000-0000-0000-00000000a003','Monitor Wadata','ewm','Benue','Makurdi','Ankpa/Wadata', true, false),
  ('00000000-0000-0000-0000-00000000a004','Admin','admin','Benue','Makurdi','North Bank I', true, false),
  ('00000000-0000-0000-0000-00000000a005','Verifier','ewv','Benue','Makurdi','North Bank I', true, false),
  -- `app_role()` returns 'user' for this one: a staff role the migration must
  -- NOT turn into an Appwrite label.
  ('00000000-0000-0000-0000-00000000a006','Pending Admin','admin','Benue','Makurdi','North Bank I', false, false)
) as v(id, name, role, state, lga, ward, appr, dis)
where profiles.id = v.id;

insert into public.reports (id, user_id, hazard_type, description, state, lga, ward, status) values
  ('00000000-0000-0000-0000-0000000b0001','00000000-0000-0000-0000-00000000a001','flood','citizen report North Bank','Benue','Makurdi','North Bank I','pending'),
  ('00000000-0000-0000-0000-0000000b0002','00000000-0000-0000-0000-00000000a003','fire','wadata report','Benue','Makurdi','Ankpa/Wadata','pending'),
  ('00000000-0000-0000-0000-0000000b0003','00000000-0000-0000-0000-00000000a002','windstorm','north bank own report','Benue','Makurdi','North Bank I','approved')
on conflict (id) do nothing;

-- The declined rows. `reports.lga` is NOT NULL, so a legacy orphan carries the
-- empty string rather than null; `copy-tables.mjs` skips on `!row.lga`, which
-- is falsy for both.
insert into public.reports (id, user_id, hazard_type, description, state, lga, ward, status) values
  ('00000000-0000-0000-0000-0000000b0f01', null, 'flood','legacy orphan, blank lga','','','','pending'),
  ('00000000-0000-0000-0000-0000000b0f02', null, 'fire','legacy orphan, blank lga 2','','','','pending')
on conflict (id) do nothing;

insert into public.verifications (id, report_id, verifier_id, is_confirmed, comment) values
  ('00000000-0000-0000-0000-0000000c0001','00000000-0000-0000-0000-0000000b0001','00000000-0000-0000-0000-00000000a005', true, 'confirmed by ewv'),
  -- On an orphan report, so the copier's second skip is exercised too: a vote
  -- on a report that did not migrate has no ward to be read by.
  ('00000000-0000-0000-0000-0000000c0f01','00000000-0000-0000-0000-0000000b0f01','00000000-0000-0000-0000-00000000a005', true, 'vote on an orphan')
on conflict (id) do nothing;

insert into public.alerts (id, title, message, severity, target_state, target_lga, is_active) values
  ('00000000-0000-0000-0000-0000000d0001','Flood warning','Rising water','warning','Benue','Makurdi', true),
  ('00000000-0000-0000-0000-0000000d0002','All clear','Receded','info','Benue','All', true)
on conflict (id) do nothing;

insert into public.authorities (id, name, organization, phone, coverage_state, coverage_lga) values
  ('00000000-0000-0000-0000-0000000e0001','NEMA Benue','NEMA','+2348000000001','Benue','Makurdi'),
  ('00000000-0000-0000-0000-0000000e0002','Fire Service','FS','+2348000000002','Benue','Makurdi')
on conflict (id) do nothing;

-- Storage, for the gate's presence comparison and `copy-storage.mjs`. The
-- paths matter: `storage-ids.mjs` derives each Appwrite file id from the path,
-- and a file under any other id is unreachable to the app.
insert into storage.buckets (id, name, public) values
  ('report-images','report-images', true),
  ('profile-images','profile-images', true)
on conflict (id) do nothing;
insert into storage.objects (bucket_id, name) values
  ('report-images','00000000-0000-0000-0000-00000000a001/flood-1.jpg'),
  ('report-images','00000000-0000-0000-0000-00000000a003/fire-1.jpg'),
  ('profile-images','00000000-0000-0000-0000-00000000a004/avatar.png');

-- Supabase URLs still sitting on rows, one per column `copy-storage.mjs`
-- rewrites. Exactly one each: the suite asserts "1 of N row(s) rewritten",
-- which is also what catches a rewrite that silently matched nothing. The host
-- is irrelevant — only the path after `/storage/v1/object/` is parsed — but the
-- object name must be one of the three above, or the rewrite would point the
-- row at a file that was never copied.
update public.reports
   set image_urls = array[
         'https://example.supabase.co/storage/v1/object/public/report-images/00000000-0000-0000-0000-00000000a001/flood-1.jpg'
       ]
 where id = '00000000-0000-0000-0000-0000000b0001';

update public.profiles
   set profile_image_url =
         'https://example.supabase.co/storage/v1/object/public/profile-images/00000000-0000-0000-0000-00000000a004/avatar.png'
 where id = '00000000-0000-0000-0000-00000000a004';

-- `knowledge_base` is seeded by the builtin-content migration, so this picks a
-- row rather than inserting one.
update public.knowledge_base
   set image_url =
         'https://example.supabase.co/storage/v1/object/public/report-images/00000000-0000-0000-0000-00000000a003/fire-1.jpg'
 where id = (select id from public.knowledge_base order by id limit 1);
