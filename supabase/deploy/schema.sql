-- ============================================================================
--  CRADI / EWER — consolidated Supabase schema
-- ============================================================================
--
--  GENERATED FILE — do not edit by hand.
--  Regenerate with:  ./supabase/deploy/build.sh
--  Source of truth:  supabase/migrations/*.sql
--
--  What this is
--    Every migration under supabase/migrations/, concatenated in filename
--    order, so the whole schema can be pasted into the Supabase SQL editor
--    (Dashboard > SQL Editor > New query) in one go. Nothing is added,
--    removed or rewritten: each migration appears verbatim below its banner.
--
--  Run it on an EMPTY project only.
--    The migrations create tables, types, functions and policies outright
--    (`create table public.x (...)`, `create policy ...`), so a second run,
--    or a run against a project that already has this schema, fails with
--    "already exists". If you need to re-run it, reset the database first
--    (Dashboard > Settings > General > Reset database) or drop the objects.
--
--  What it expects the project to already provide (real Supabase does):
--    * the roles `anon`, `authenticated` and `service_role`
--    * the `auth` schema with `auth.users` and `auth.uid()`
--    * the `storage` schema with `storage.buckets`, `storage.objects`
--      (RLS already enabled) and `storage.foldername()`
--    * the `supabase_realtime` publication
--    * a role that owns/administers the above — i.e. run it as `postgres`,
--      which is what the dashboard SQL editor uses. It creates triggers on
--      `auth.users` and policies on `storage.objects`.
--
--    supabase/tests/local_stubs.sql fakes these for plain-Postgres testing.
--    It is deliberately NOT part of this file: never run local_stubs.sql
--    against a real Supabase project.
--
--  Storage buckets `report-images` and `profile-images` are created by the
--  init migration (public read, 5 MB, image mime types) — no manual setup.
--
--  After a successful run the `public` schema holds 21 tables.
--
--  Source migrations, in the order applied:
--     1. 20260925000000_init.sql
--     2. 20260926000000_report_disputes.sql
--     3. 20260926010000_reopen_scope_audit.sql
--     4. 20260926020000_workflow_hardening.sql
--     5. 20260927000000_security_hardening.sql
--     6. 20260927010000_approval_confirmed_and_sync_retry.sql
--     7. 20260927020000_access_sync_and_settings_cleanup.sql
--     8. 20260927030000_authorities_coverage_state.sql
--     9. 20260927040000_builtin_content.sql
--    10. 20260927050000_alert_target_state.sql
--    11. 20260927060000_integrity_hardening.sql
--    12. 20260927070000_backfill_alert_target_state.sql
--    13. 20260927080000_alert_state_required.sql
--    14. 20260927090000_authority_state_required.sql
-- ============================================================================


-- ============================================================================
-- SOURCE: supabase/migrations/20260925000000_init.sql
-- ============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
--  CRADI / EWER — Supabase schema (replaces Firestore project ewer-8f788)
--
--  Conventions
--    * snake_case columns; the Flutter data layer converts to/from camelCase.
--    * Every table has RLS enabled. The service role (Railway backend, admin
--      API routes, migration script) bypasses RLS.
--    * A user's role only takes effect once an admin approves the account and
--      it is not disabled (see app_role()). Self-selected roles grant nothing.
--    * Server-side side effects (push, email, escalation) are queued in
--      notification_outbox by triggers and processed by the Railway backend.
-- ─────────────────────────────────────────────────────────────────────────────

create extension if not exists pgcrypto;

-- ── Settings (replaces Firebase Remote Config) ──────────────────────────────

create table public.app_settings (
  key         text primary key,
  value       jsonb not null,
  updated_at  timestamptz not null default now()
);

insert into public.app_settings (key, value) values
  ('minimum_peer_confirmations', '2'),
  ('escalation_timeout_minutes', '30'),
  ('max_sms_per_lga_per_day', '50'),
  ('max_sms_per_alert_event', '20'),
  ('sms_dedup_window_minutes', '60'),
  ('content_cache_ttl_hours', '24'),
  ('max_report_image_mb', '5'),
  ('feature_flag_peer_chat', 'true'),
  ('feature_flag_voice_reports', 'false'),
  ('app_min_version', '"1.0.0"'),
  ('app_min_version_message', '"Please update the EWER app to continue."');

create or replace function public.setting_int(p_key text, p_default int)
returns int language plpgsql stable security definer set search_path = public as $$
begin
  return coalesce((select (value #>> '{}')::int from app_settings where key = p_key), p_default);
exception when others then
  -- A malformed setting must never break report inserts.
  return p_default;
end $$;

-- ── Generic updated_at trigger ──────────────────────────────────────────────

create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- ── Profiles (replaces users/{uid}) ─────────────────────────────────────────

create table public.profiles (
  id                  uuid primary key references auth.users (id) on delete cascade,
  email               text,
  name                text not null default 'User',
  role                text not null default 'user' check (role in (
                        'user', 'ewm', 'ewv', 'ewr', 'ldp_coordinator',
                        'project_staff', 'admin', 'techSupport')),
  address             text not null default '',
  state               text not null default '',
  lga                 text not null default '',
  ward                text not null default '',
  phone               text not null default '',
  is_verified         boolean not null default false,
  is_approved         boolean not null default false,
  is_disabled         boolean not null default false,
  biometrics_enabled  boolean not null default false,
  profile_image_url   text not null default '',
  monitoring_zone     text not null default '',
  registration_code   text,
  last_login_at       timestamptz,
  legacy_firebase_uid text unique,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create index profiles_role_lga_idx on public.profiles (role, lga);
create index profiles_ward_lga_role_idx on public.profiles (ward, lga, role);

create trigger profiles_touch before update on public.profiles
  for each row execute function public.touch_updated_at();

-- Role helpers. SECURITY DEFINER so they can read profiles without recursing
-- through the profiles RLS policies.

create or replace function public.app_role()
returns text language sql stable security definer set search_path = public as $$
  select coalesce(
    (select case when p.is_approved and not p.is_disabled then p.role else 'user' end
       from profiles p where p.id = auth.uid()),
    'user')
$$;

create or replace function public.is_admin()
returns boolean language sql stable as $$ select public.app_role() = 'admin' $$;

create or replace function public.is_staff()
returns boolean language sql stable as $$
  select public.app_role() in ('ewm', 'ewv', 'ewr', 'ldp_coordinator', 'project_staff', 'admin', 'techSupport')
$$;

create or replace function public.is_verifier()
returns boolean language sql stable as $$
  select public.app_role() in ('ewm', 'ewv', 'ewr', 'admin')
$$;

create or replace function public.is_enabled_user()
returns boolean language sql stable security definer set search_path = public as $$
  select auth.uid() is not null
     and coalesce((select not is_disabled from profiles where id = auth.uid()), true)
$$;

create or replace function public.my_ward()
returns text language sql stable security definer set search_path = public as $$
  select ward from profiles where id = auth.uid()
$$;

create or replace function public.auth_user_confirmed(p_user_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from auth.users u
     where u.id = p_user_id
       and (u.email_confirmed_at is not null or u.phone_confirmed_at is not null))
$$;

-- Non-admins may not change privileged columns on their own profile.
create or replace function public.guard_profile_update()
returns trigger language plpgsql as $$
begin
  -- pg_trigger_depth() > 1: nested write from one of our own trusted triggers
  -- (e.g. auth.users → profiles sync), not a direct client update.
  if auth.uid() is not null and pg_trigger_depth() = 1 and not public.is_admin() then
    if new.role is distinct from old.role
       or new.is_approved is distinct from old.is_approved
       or new.is_disabled is distinct from old.is_disabled
       or new.email is distinct from old.email
       or new.legacy_firebase_uid is distinct from old.legacy_firebase_uid
       or new.registration_code is distinct from old.registration_code
       or new.id is distinct from old.id then
      raise exception 'Only an admin can change role, approval, disabled status or email'
        using errcode = '42501';
    end if;
    -- Approved staff are scoped by location (ward-level report access and
    -- verification requests), so only an admin may move them.
    if old.is_approved and old.role <> 'user'
       and (new.ward is distinct from old.ward
            or new.lga is distinct from old.lga
            or new.state is distinct from old.state) then
      raise exception 'Ask an admin to change the location of a staff account'
        using errcode = '42501';
    end if;
    -- is_verified may only be raised once Supabase Auth has confirmed the user.
    if new.is_verified and not old.is_verified and not public.auth_user_confirmed(new.id) then
      raise exception 'Account is not verified yet' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;

create trigger profiles_guard before update on public.profiles
  for each row execute function public.guard_profile_update();

-- Create a profile for every new auth user, from signUp metadata.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  meta jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  requested_role text := coalesce(meta ->> 'role', 'user');
begin
  if requested_role not in ('user', 'ewm', 'ewv', 'ewr', 'ldp_coordinator', 'project_staff') then
    requested_role := 'user';
  end if;

  insert into profiles (id, email, phone, name, role, address, state, lga, ward, is_verified)
  values (
    new.id,
    new.email,
    coalesce(case when new.phone is null or new.phone = '' then null
                  when left(new.phone, 1) = '+' then new.phone
                  else '+' || new.phone end,
             meta ->> 'phone', ''),
    coalesce(nullif(meta ->> 'name', ''), 'User'),
    requested_role,
    coalesce(meta ->> 'address', ''),
    coalesce(meta ->> 'state', ''),
    coalesce(meta ->> 'lga', ''),
    coalesce(meta ->> 'ward', ''),
    new.email_confirmed_at is not null or new.phone_confirmed_at is not null
  )
  on conflict (id) do nothing;
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Keep email / phone / verification in sync with Supabase Auth.
create or replace function public.handle_auth_user_updated()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update profiles
     set email = new.email,
         phone = case
                   when new.phone is null or new.phone = '' then phone
                   when left(new.phone, 1) = '+' then new.phone
                   else '+' || new.phone
                 end,
         is_verified = is_verified
                       or new.email_confirmed_at is not null
                       or new.phone_confirmed_at is not null
   where id = new.id;
  return new;
end $$;

create trigger on_auth_user_updated after update of email, phone, email_confirmed_at, phone_confirmed_at
  on auth.users for each row execute function public.handle_auth_user_updated();

alter table public.profiles enable row level security;

create policy profiles_select on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_staff());

create policy profiles_update on public.profiles for update to authenticated
  using (id = auth.uid() or public.is_admin())
  with check (id = auth.uid() or public.is_admin());

create policy profiles_delete on public.profiles for delete to authenticated
  using (public.is_admin());

-- ── Notification outbox (processed by the Railway backend) ──────────────────

create table public.notification_outbox (
  id            bigint generated always as identity primary key,
  event_type    text not null,
  payload       jsonb not null default '{}'::jsonb,
  created_at    timestamptz not null default now(),
  available_at  timestamptz not null default now(),
  processed_at  timestamptz,
  attempts      int not null default 0,
  last_error    text
);

create index notification_outbox_pending_idx
  on public.notification_outbox (available_at) where processed_at is null;

alter table public.notification_outbox enable row level security;
-- No policies: only the service role can read or write.

-- Claim a batch of due events (used by the backend worker).
create or replace function public.claim_outbox_events(p_limit int default 50)
returns setof public.notification_outbox
language sql security definer set search_path = public as $$
  update notification_outbox o
     set attempts = o.attempts + 1,
         available_at = now() + make_interval(mins => least(60, power(2, o.attempts)::int))
   where o.id in (
     select id from notification_outbox
      where processed_at is null and available_at <= now() and attempts < 8
      order by id
      limit p_limit
      for update skip locked)
  returning o.*;
$$;

revoke all on function public.claim_outbox_events(int) from public, anon, authenticated;

-- ── Reports ─────────────────────────────────────────────────────────────────

create table public.reports (
  id                       uuid primary key default gen_random_uuid(),
  user_id                  uuid references public.profiles (id) on delete set null,
  reporter_name            text,
  hazard_type              text not null,
  severity                 text not null default 'medium'
                             check (severity in ('low', 'medium', 'high', 'critical')),
  latitude                 double precision,
  longitude                double precision,
  location_details         text not null default '',
  location                 text not null default '',
  address                  text not null default '',
  ward                     text not null default '',
  lga                      text not null,
  state                    text not null default '',
  description              text not null default '',
  submitted_at             timestamptz not null default now(),
  image_urls               text[] not null default '{}',
  status                   text not null default 'pending'
                             check (status in ('pending', 'verified', 'approved', 'rejected')),
  type                     text,
  is_alert                 boolean not null default false,
  verification_count       int not null default 0,
  verified_at              timestamptz,
  auto_validated           boolean not null default false,
  approved_at              timestamptz,
  rejected_at              timestamptz,
  rejection_reason         text,
  escalated                boolean not null default false,
  escalated_at             timestamptz,
  escalation_reason        text,
  escalation_scheduled_at  timestamptz,
  escalation_status        text,
  updated_by               uuid,
  synced_at                timestamptz,
  legacy_firebase_id       text unique,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now()
);

create index reports_user_submitted_idx on public.reports (user_id, submitted_at desc);
create index reports_status_submitted_idx on public.reports (status, submitted_at desc);
create index reports_state_status_idx on public.reports (state, status, submitted_at desc);
create index reports_lga_status_idx on public.reports (lga, status, submitted_at desc);
create index reports_ward_status_idx on public.reports (ward, status, submitted_at desc);

create trigger reports_touch before update on public.reports
  for each row execute function public.touch_updated_at();

create or replace function public.reports_before_insert()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.reporter_name is null and new.user_id is not null then
    select name into new.reporter_name from profiles where id = new.user_id;
  end if;
  new.is_alert := new.severity in ('high', 'critical');
  if new.status = 'pending' then
    new.escalation_scheduled_at :=
      now() + make_interval(mins => public.setting_int('escalation_timeout_minutes', 30));
    new.escalation_status := 'pending';
  end if;
  return new;
end $$;

create trigger reports_before_insert before insert on public.reports
  for each row execute function public.reports_before_insert();

-- Non-staff owners may edit a pending report's content, but not its workflow state.
create or replace function public.guard_report_update()
returns trigger language plpgsql as $$
declare
  r text;
  workflow_changed boolean;
begin
  -- Service role (auth.uid() null) and our own nested triggers are trusted.
  if auth.uid() is not null and pg_trigger_depth() = 1 then
    r := public.app_role();
    workflow_changed :=
         new.status is distinct from old.status
      or new.approved_at is distinct from old.approved_at
      or new.rejected_at is distinct from old.rejected_at
      or new.rejection_reason is distinct from old.rejection_reason;

    if new.user_id is distinct from old.user_id
       or new.escalated is distinct from old.escalated
       or new.escalation_status is distinct from old.escalation_status
       or new.escalated_at is distinct from old.escalated_at then
      if r <> 'admin' then
        raise exception 'Only an admin can change report ownership or escalation'
          using errcode = '42501';
      end if;
    end if;

    -- Peer verification is counted by the verifications trigger, never by hand.
    if new.verification_count is distinct from old.verification_count
       or new.verified_at is distinct from old.verified_at
       or new.auto_validated is distinct from old.auto_validated
       or (new.status = 'verified' and old.status <> 'verified') then
      if r <> 'admin' then
        raise exception 'Reports are verified by peer confirmations' using errcode = '42501';
      end if;
    end if;

    if workflow_changed then
      if r not in ('ewv', 'ewr', 'ldp_coordinator', 'project_staff', 'admin') then
        raise exception 'Your role cannot approve, reject or reopen reports' using errcode = '42501';
      end if;
      if r <> 'admin' and old.user_id = auth.uid() then
        raise exception 'You cannot approve or reject your own report' using errcode = '42501';
      end if;
    end if;
  end if;
  new.is_alert := new.severity in ('high', 'critical');
  return new;
end $$;

create trigger reports_guard before update on public.reports
  for each row execute function public.guard_report_update();

-- ── Scheduled escalations ───────────────────────────────────────────────────

create table public.scheduled_escalations (
  id            uuid primary key default gen_random_uuid(),
  report_id     uuid not null references public.reports (id) on delete cascade,
  escalate_at   timestamptz not null,
  status        text not null default 'pending' check (status in ('pending', 'processed', 'skipped')),
  reason        text,
  processed_at  timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create unique index scheduled_escalations_report_pending_idx
  on public.scheduled_escalations (report_id) where status = 'pending';
create index scheduled_escalations_due_idx
  on public.scheduled_escalations (escalate_at) where status = 'pending';

create trigger scheduled_escalations_touch before update on public.scheduled_escalations
  for each row execute function public.touch_updated_at();

alter table public.scheduled_escalations enable row level security;

create policy scheduled_escalations_select on public.scheduled_escalations for select to authenticated
  using (public.app_role() in ('ldp_coordinator', 'project_staff', 'admin'));

-- New report → schedule escalation + ask ward peers to verify.
create or replace function public.reports_after_insert()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'pending' then
    insert into scheduled_escalations (report_id, escalate_at)
      values (new.id, coalesce(new.escalation_scheduled_at, now() + interval '30 minutes'))
      on conflict do nothing;
    insert into notification_outbox (event_type, payload)
      values ('report_created', jsonb_build_object('report_id', new.id));
  end if;
  return new;
end $$;

create trigger reports_after_insert after insert on public.reports
  for each row execute function public.reports_after_insert();

-- Status change → notify reporter (and broadcast when approved).
create or replace function public.reports_after_status_change()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status is distinct from old.status then
    insert into notification_outbox (event_type, payload)
      values ('report_status_changed', jsonb_build_object(
        'report_id', new.id, 'old_status', old.status, 'new_status', new.status,
        'reason', new.rejection_reason));
    if new.status <> 'pending' then
      update scheduled_escalations
         set status = 'skipped', reason = 'Status: ' || new.status, processed_at = now()
       where report_id = new.id and status = 'pending';
    end if;
  end if;
  return new;
end $$;

create trigger reports_after_status_change after update of status on public.reports
  for each row execute function public.reports_after_status_change();

alter table public.reports enable row level security;

create policy reports_insert on public.reports for insert to authenticated
  with check (
    user_id = auth.uid()
    and public.is_enabled_user()
    and status = 'pending'
    and verification_count = 0
    and not escalated
  );

create policy reports_select on public.reports for select to authenticated
  using (
    user_id = auth.uid()
    or (public.app_role() = 'ewm' and ward = public.my_ward())
    or public.app_role() in ('ewv', 'ewr', 'ldp_coordinator', 'project_staff', 'admin', 'techSupport')
  );

create policy reports_update on public.reports for update to authenticated
  using (public.is_staff() or (user_id = auth.uid() and status = 'pending'))
  with check (public.is_staff() or (user_id = auth.uid() and status = 'pending'));

create policy reports_delete on public.reports for delete to authenticated
  using (public.is_admin());

-- ── Verifications (peer confirmations) ──────────────────────────────────────

create table public.verifications (
  id            uuid primary key default gen_random_uuid(),
  report_id     uuid not null references public.reports (id) on delete cascade,
  verifier_id   uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  is_confirmed  boolean not null,
  comment       text not null default '',
  submitted_at  timestamptz not null default now(),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (report_id, verifier_id)
);

create index verifications_report_idx on public.verifications (report_id, is_confirmed);

create or replace function public.report_owner(p_report_id uuid)
returns uuid language sql stable security definer set search_path = public as $$
  select user_id from reports where id = p_report_id
$$;

-- Confirmation threshold is enforced server-side: once enough peers confirm a
-- pending report it moves to 'verified' exactly once.
create or replace function public.verifications_after_insert()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  confirmed int;
begin
  -- Serialise concurrent confirmations for the same report so each count sees
  -- the others' committed rows.
  perform 1 from reports where id = new.report_id for update;

  select count(*) into confirmed
    from verifications where report_id = new.report_id and is_confirmed;

  update reports set verification_count = confirmed where id = new.report_id;

  if confirmed >= public.setting_int('minimum_peer_confirmations', 2) then
    update reports
       set status = 'verified', verified_at = now(), auto_validated = true
     where id = new.report_id and status = 'pending';
  end if;
  return new;
end $$;

create trigger verifications_after_insert after insert on public.verifications
  for each row execute function public.verifications_after_insert();

create or replace function public.verifications_after_delete()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update reports
     set verification_count = (select count(*) from verifications
                                where report_id = old.report_id and is_confirmed)
   where id = old.report_id;
  return old;
end $$;

create trigger verifications_after_delete after delete on public.verifications
  for each row execute function public.verifications_after_delete();

create or replace function public.report_ward(p_report_id uuid)
returns text language sql stable security definer set search_path = public as $$
  select ward from reports where id = p_report_id
$$;

alter table public.verifications enable row level security;

create policy verifications_select on public.verifications for select to authenticated
  using (verifier_id = auth.uid() or public.is_verifier() or public.app_role() = 'techSupport');

create policy verifications_insert on public.verifications for insert to authenticated
  with check (
    verifier_id = auth.uid()
    and public.is_verifier()
    and public.report_owner(report_id) is distinct from auth.uid()
    and (public.app_role() <> 'ewm' or public.report_ward(report_id) = public.my_ward())
  );

create policy verifications_admin_update on public.verifications for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy verifications_admin_delete on public.verifications for delete to authenticated
  using (public.is_admin());

-- ── Verification overrides (manual approve / reject by senior staff) ────────

create table public.verification_overrides (
  id            uuid primary key default gen_random_uuid(),
  report_id     uuid not null references public.reports (id) on delete cascade,
  validator_id  uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  action        text not null check (action in ('approved', 'rejected')),
  reason        text not null default '',
  created_at    timestamptz not null default now()
);

alter table public.verification_overrides enable row level security;

create policy verification_overrides_select on public.verification_overrides for select to authenticated
  using (public.app_role() in ('ewv', 'ewr', 'ldp_coordinator', 'project_staff', 'admin', 'techSupport'));

create policy verification_overrides_insert on public.verification_overrides for insert to authenticated
  with check (
    validator_id = auth.uid()
    and public.app_role() in ('ewv', 'ewr', 'ldp_coordinator', 'project_staff', 'admin')
  );

-- ── Alerts (community broadcasts) ───────────────────────────────────────────

create table public.alerts (
  id          uuid primary key default gen_random_uuid(),
  title       text not null,
  message     text not null default '',
  severity    text not null default 'info' check (severity in ('info', 'warning', 'critical')),
  target_lga  text not null default 'All',
  report_id   uuid references public.reports (id) on delete set null,
  created_by  uuid default auth.uid() references public.profiles (id) on delete set null,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index alerts_active_created_idx on public.alerts (is_active, created_at desc);
create index alerts_created_idx on public.alerts (created_at desc);

create trigger alerts_touch before update on public.alerts
  for each row execute function public.touch_updated_at();

create or replace function public.alerts_after_insert()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.is_active then
    insert into notification_outbox (event_type, payload)
      values ('alert_created', jsonb_build_object('alert_id', new.id));
  end if;
  return new;
end $$;

create trigger alerts_after_insert after insert on public.alerts
  for each row execute function public.alerts_after_insert();

alter table public.alerts enable row level security;

create policy alerts_select on public.alerts for select to authenticated using (true);

create policy alerts_write on public.alerts for all to authenticated
  using (public.app_role() in ('ewv', 'ewr', 'ldp_coordinator', 'project_staff', 'admin', 'techSupport'))
  with check (public.app_role() in ('ewv', 'ewr', 'ldp_coordinator', 'project_staff', 'admin', 'techSupport'));

-- ── Chat messages ───────────────────────────────────────────────────────────

create table public.messages (
  id           uuid primary key default gen_random_uuid(),
  chat_id      text not null default 'general',
  sender_id    uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  sender_name  text not null default '',
  message      text not null,
  type         text not null default 'text',
  sent_at      timestamptz not null default now(),
  read         boolean not null default false,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index messages_chat_sent_idx on public.messages (chat_id, sent_at desc);

create trigger messages_touch before update on public.messages
  for each row execute function public.touch_updated_at();

alter table public.messages enable row level security;

create policy messages_select on public.messages for select to authenticated using (true);

create policy messages_insert on public.messages for insert to authenticated
  with check (sender_id = auth.uid() and public.is_enabled_user());

create policy messages_update on public.messages for update to authenticated
  using (sender_id = auth.uid()) with check (sender_id = auth.uid());

create policy messages_delete on public.messages for delete to authenticated
  using (sender_id = auth.uid() or public.is_admin());

-- ── Personal emergency contacts ─────────────────────────────────────────────

create table public.contacts (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  name          text not null,
  role          text not null default '',
  phone         text not null,
  organization  text,
  lga           text,
  category      text not null default 'other',
  is_available  boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index contacts_user_idx on public.contacts (user_id, category);

create trigger contacts_touch before update on public.contacts
  for each row execute function public.touch_updated_at();

alter table public.contacts enable row level security;

create policy contacts_owner on public.contacts for all to authenticated
  using (user_id = auth.uid() or public.is_admin())
  with check (user_id = auth.uid() or public.is_admin());

-- ── Knowledge base ──────────────────────────────────────────────────────────

create table public.knowledge_base (
  id           uuid primary key default gen_random_uuid(),
  title        text not null,
  content      text not null default '',
  source       text not null default '',
  category     text not null default 'General',
  hazard_type  text not null default 'general',
  image_url    text,
  legacy_firebase_id text unique,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index knowledge_base_hazard_idx on public.knowledge_base (hazard_type, updated_at desc);

create trigger knowledge_base_touch before update on public.knowledge_base
  for each row execute function public.touch_updated_at();

alter table public.knowledge_base enable row level security;

create policy knowledge_base_select on public.knowledge_base for select to authenticated using (true);

create policy knowledge_base_write on public.knowledge_base for all to authenticated
  using (public.app_role() in ('admin', 'techSupport'))
  with check (public.app_role() in ('admin', 'techSupport'));

-- ── Authorities (SMS alert recipients per LGA) ──────────────────────────────

create table public.authorities (
  id            uuid primary key default gen_random_uuid(),
  name          text not null default '',
  organization  text,
  phone         text not null,
  coverage_lga  text not null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index authorities_lga_idx on public.authorities (coverage_lga);

create trigger authorities_touch before update on public.authorities
  for each row execute function public.touch_updated_at();

alter table public.authorities enable row level security;

create policy authorities_select on public.authorities for select to authenticated
  using (public.is_staff());

create policy authorities_write on public.authorities for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ── Trusted devices / login history (fraud detection) ───────────────────────

create table public.trusted_devices (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  device_fingerprint  text not null,
  device_name         text not null default '',
  trusted             boolean not null default true,
  last_used           timestamptz not null default now(),
  created_at          timestamptz not null default now(),
  unique (user_id, device_fingerprint)
);

alter table public.trusted_devices enable row level security;

create policy trusted_devices_select on public.trusted_devices for select to authenticated
  using (user_id = auth.uid());
create policy trusted_devices_insert on public.trusted_devices for insert to authenticated
  with check (user_id = auth.uid());
create policy trusted_devices_delete on public.trusted_devices for delete to authenticated
  using (user_id = auth.uid());

create table public.login_history (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  success             boolean not null,
  device_fingerprint  text not null default '',
  device_name         text not null default '',
  risk_score          int not null default 0,
  occurred_at         timestamptz not null default now(),
  created_at          timestamptz not null default now()
);

create index login_history_user_idx on public.login_history (user_id, occurred_at desc);

alter table public.login_history enable row level security;

create policy login_history_select on public.login_history for select to authenticated
  using (user_id = auth.uid() or public.is_admin());
create policy login_history_insert on public.login_history for insert to authenticated
  with check (user_id = auth.uid());

-- ── NDPA consent records ────────────────────────────────────────────────────

create table public.ndpa_consents (
  user_id         uuid primary key default auth.uid() references public.profiles (id) on delete cascade,
  consented_at    timestamptz not null default now(),
  policy_version  text not null,
  data_residency  text not null default '',
  platform        text not null default 'mobile',
  method          text not null default ''
);

alter table public.ndpa_consents enable row level security;

create policy ndpa_consents_select on public.ndpa_consents for select to authenticated
  using (user_id = auth.uid() or public.is_admin());
create policy ndpa_consents_insert on public.ndpa_consents for insert to authenticated
  with check (user_id = auth.uid());

-- ── app_settings access ─────────────────────────────────────────────────────

alter table public.app_settings enable row level security;

create policy app_settings_select on public.app_settings for select to anon, authenticated using (true);
create policy app_settings_write on public.app_settings for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ── Storage buckets ─────────────────────────────────────────────────────────
-- Public-read buckets (URLs are stored on rows, like Firebase download URLs);
-- users may only write inside a folder named after their own user id.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('report-images', 'report-images', true, 5242880, array['image/jpeg', 'image/png', 'image/webp', 'image/heic']),
  ('profile-images', 'profile-images', true, 5242880, array['image/jpeg', 'image/png', 'image/webp', 'image/heic'])
on conflict (id) do nothing;

create policy "users upload own images" on storage.objects for insert to authenticated
  with check (
    bucket_id in ('report-images', 'profile-images')
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "users read own images" on storage.objects for select to authenticated
  using (
    bucket_id in ('report-images', 'profile-images')
    and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin())
  );

create policy "users update own images" on storage.objects for update to authenticated
  using (
    bucket_id in ('report-images', 'profile-images')
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "users delete own images" on storage.objects for delete to authenticated
  using (
    bucket_id in ('report-images', 'profile-images')
    and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin())
  );

-- ── Realtime ────────────────────────────────────────────────────────────────

alter publication supabase_realtime add table
  public.profiles, public.reports, public.alerts, public.messages,
  public.contacts, public.knowledge_base;

-- ── Function privileges ─────────────────────────────────────────────────────
-- SECURITY DEFINER helpers are only for signed-in users (RLS policies need
-- them); never expose them to anonymous API callers.
revoke execute on function
  public.setting_int(text, int), public.app_role(), public.is_enabled_user(),
  public.my_ward(), public.auth_user_confirmed(uuid), public.report_owner(uuid),
  public.report_ward(uuid)
  from public, anon;
grant execute on function
  public.setting_int(text, int), public.app_role(), public.is_enabled_user(),
  public.my_ward(), public.auth_user_confirmed(uuid), public.report_owner(uuid),
  public.report_ward(uuid)
  to authenticated, service_role;


-- ============================================================================
-- SOURCE: supabase/migrations/20260926000000_report_disputes.sql
-- ============================================================================

-- A peer disputing a pending report escalates it immediately (handled by the
-- Railway backend via the 'report_disputed' outbox event).

create or replace function public.verifications_after_insert_dispute()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not new.is_confirmed and exists (
       select 1 from reports
        where id = new.report_id and status = 'pending' and not escalated) then
    insert into notification_outbox (event_type, payload)
      values ('report_disputed', jsonb_build_object(
        'report_id', new.report_id, 'verification_id', new.id));
  end if;
  return new;
end $$;

create trigger verifications_after_insert_dispute after insert on public.verifications
  for each row execute function public.verifications_after_insert_dispute();


-- ============================================================================
-- SOURCE: supabase/migrations/20260926010000_reopen_scope_audit.sql
-- ============================================================================

-- 1. Reopen: moving a report back to 'pending' clears its peer votes so it can
--    be verified again, and re-schedules escalation / verification requests.
-- 2. Ward names repeat across LGAs, so EWM scoping compares (lga, ward).
-- 3. Staff approve / reject decisions are audited automatically.

create or replace function public.my_lga()
returns text language sql stable security definer set search_path = public as $$
  select lga from profiles where id = auth.uid()
$$;

create or replace function public.report_lga(p_report_id uuid)
returns text language sql stable security definer set search_path = public as $$
  select lga from reports where id = p_report_id
$$;

revoke execute on function public.my_lga(), public.report_lga(uuid) from public, anon;
grant execute on function public.my_lga(), public.report_lga(uuid) to authenticated, service_role;

drop policy reports_select on public.reports;
create policy reports_select on public.reports for select to authenticated
  using (
    user_id = auth.uid()
    or (public.app_role() = 'ewm' and ward = public.my_ward() and lga = public.my_lga())
    or public.app_role() in ('ewv', 'ewr', 'ldp_coordinator', 'project_staff', 'admin', 'techSupport')
  );

drop policy verifications_insert on public.verifications;
create policy verifications_insert on public.verifications for insert to authenticated
  with check (
    verifier_id = auth.uid()
    and public.is_verifier()
    and public.report_owner(report_id) is distinct from auth.uid()
    and (public.app_role() <> 'ewm'
         or (public.report_ward(report_id) = public.my_ward()
             and public.report_lga(report_id) = public.my_lga()))
  );

-- Trusted server functions mark their own writes so the client-update guard
-- lets them through. The flag is transaction-local and set_config is not
-- reachable through the API (only the public schema is exposed).
create or replace function public.guard_report_update_trusted()
returns boolean language sql stable as $$
  select coalesce(current_setting('cradi.trusted_write', true), '') = 'on'
$$;

create or replace function public.guard_report_update()
returns trigger language plpgsql as $$
declare
  r text;
  workflow_changed boolean;
begin
  if auth.uid() is not null and pg_trigger_depth() = 1
     and not public.guard_report_update_trusted() then
    r := public.app_role();
    workflow_changed :=
         new.status is distinct from old.status
      or new.approved_at is distinct from old.approved_at
      or new.rejected_at is distinct from old.rejected_at
      or new.rejection_reason is distinct from old.rejection_reason;

    if new.user_id is distinct from old.user_id
       or new.escalated is distinct from old.escalated
       or new.escalation_status is distinct from old.escalation_status
       or new.escalated_at is distinct from old.escalated_at then
      if r <> 'admin' then
        raise exception 'Only an admin can change report ownership or escalation'
          using errcode = '42501';
      end if;
    end if;

    if new.verification_count is distinct from old.verification_count
       or new.verified_at is distinct from old.verified_at
       or new.auto_validated is distinct from old.auto_validated
       or (new.status = 'verified' and old.status <> 'verified') then
      if r <> 'admin' then
        raise exception 'Reports are verified by peer confirmations' using errcode = '42501';
      end if;
    end if;

    if workflow_changed then
      if r not in ('ewv', 'ewr', 'ldp_coordinator', 'project_staff', 'admin') then
        raise exception 'Your role cannot approve, reject or reopen reports' using errcode = '42501';
      end if;
      if r <> 'admin' and old.user_id = auth.uid() then
        raise exception 'You cannot approve or reject your own report' using errcode = '42501';
      end if;
    end if;
  end if;
  new.is_alert := new.severity in ('high', 'critical');
  return new;
end $$;

-- Coordinators and project staff review peer votes too.
drop policy verifications_select on public.verifications;
create policy verifications_select on public.verifications for select to authenticated
  using (
    verifier_id = auth.uid()
    or public.app_role() in ('ewm', 'ewv', 'ewr', 'ldp_coordinator', 'project_staff', 'admin', 'techSupport')
  );

-- Reopen a report (senior staff / admin, never your own report).
create or replace function public.reopen_report(p_report_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  r text := public.app_role();
  owner uuid;
begin
  if r not in ('ewv', 'ewr', 'ldp_coordinator', 'project_staff', 'admin') then
    raise exception 'Your role cannot reopen reports' using errcode = '42501';
  end if;

  select user_id into owner from reports where id = p_report_id for update;
  if not found then
    raise exception 'Report not found' using errcode = 'P0002';
  end if;
  if r <> 'admin' and owner = auth.uid() then
    raise exception 'You cannot reopen your own report' using errcode = '42501';
  end if;

  perform set_config('cradi.trusted_write', 'on', true);

  delete from verifications where report_id = p_report_id;

  update reports
     set status = 'pending',
         verification_count = 0,
         verified_at = null,
         auto_validated = false,
         approved_at = null,
         rejected_at = null,
         rejection_reason = null,
         escalated = false,
         escalated_at = null,
         escalation_reason = null,
         escalation_scheduled_at =
           now() + make_interval(mins => public.setting_int('escalation_timeout_minutes', 30)),
         escalation_status = 'pending',
         updated_by = auth.uid()
   where id = p_report_id;

  update scheduled_escalations
     set status = 'skipped', reason = 'Report reopened', processed_at = now()
   where report_id = p_report_id and status = 'pending';

  insert into scheduled_escalations (report_id, escalate_at)
    select id, escalation_scheduled_at from reports where id = p_report_id;

  insert into notification_outbox (event_type, payload)
    values ('report_created', jsonb_build_object('report_id', p_report_id, 'reopened', true));

  perform set_config('cradi.trusted_write', '', true);
end $$;

revoke execute on function public.reopen_report(uuid) from public, anon;
grant execute on function public.reopen_report(uuid) to authenticated;

-- Audit staff approve / reject decisions made directly on reports.
create or replace function public.reports_audit_decision()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null
     and new.status is distinct from old.status
     and new.status in ('approved', 'rejected') then
    insert into verification_overrides (report_id, validator_id, action, reason)
      values (new.id, auth.uid(), new.status, coalesce(new.rejection_reason, ''));
  end if;
  return new;
end $$;

create trigger reports_audit_decision after update of status on public.reports
  for each row execute function public.reports_audit_decision();


-- ============================================================================
-- SOURCE: supabase/migrations/20260926020000_workflow_hardening.sql
-- ============================================================================

-- Workflow hardening from the cross-system audit:
--  * reopening only through reopen_report() (a plain status → 'pending' update
--    left stale votes and no escalation / verification request)
--  * reopen_report refuses reports that are already pending
--  * votes only on pending reports; admin vote edits are recounted
--  * only the owner (or an admin) edits report content; location is frozen
--    once peers have voted
--  * status changes clear the previous decision's columns server-side
--  * admin 'verified' decisions are audited; audit rows survive user deletion

-- ── Audit trail survives user deletion ──────────────────────────────────────
alter table public.verification_overrides
  alter column validator_id drop not null,
  drop constraint verification_overrides_validator_id_fkey,
  add constraint verification_overrides_validator_id_fkey
    foreign key (validator_id) references public.profiles (id) on delete set null,
  drop constraint verification_overrides_action_check,
  add constraint verification_overrides_action_check
    check (action in ('approved', 'rejected', 'verified'));

-- ── Report guard (final definition) ─────────────────────────────────────────
create or replace function public.guard_report_update()
returns trigger language plpgsql as $$
declare
  r text;
  workflow_changed boolean;
  content_changed boolean;
  location_changed boolean;
begin
  if auth.uid() is not null and pg_trigger_depth() = 1
     and not public.guard_report_update_trusted() then
    r := public.app_role();

    if new.status = 'pending' and old.status is distinct from 'pending' then
      raise exception 'Use reopen_report() to move a report back to pending'
        using errcode = '42501';
    end if;

    workflow_changed :=
         new.status is distinct from old.status
      or new.approved_at is distinct from old.approved_at
      or new.rejected_at is distinct from old.rejected_at
      or new.rejection_reason is distinct from old.rejection_reason;

    location_changed :=
         new.ward is distinct from old.ward
      or new.lga is distinct from old.lga
      or new.state is distinct from old.state
      or new.latitude is distinct from old.latitude
      or new.longitude is distinct from old.longitude;

    content_changed := location_changed
      or new.hazard_type is distinct from old.hazard_type
      or new.severity is distinct from old.severity
      or new.description is distinct from old.description
      or new.location_details is distinct from old.location_details
      or new.location is distinct from old.location
      or new.address is distinct from old.address
      or new.image_urls is distinct from old.image_urls
      or new.submitted_at is distinct from old.submitted_at
      or new.type is distinct from old.type;

    if content_changed and r <> 'admin' then
      if old.user_id is distinct from auth.uid() then
        raise exception 'Only the reporter can edit a report''s details' using errcode = '42501';
      end if;
      if location_changed and old.verification_count > 0 then
        raise exception 'The location cannot change after peers have verified the report'
          using errcode = '42501';
      end if;
    end if;

    if new.user_id is distinct from old.user_id
       or new.escalated is distinct from old.escalated
       or new.escalation_status is distinct from old.escalation_status
       or new.escalated_at is distinct from old.escalated_at then
      if r <> 'admin' then
        raise exception 'Only an admin can change report ownership or escalation'
          using errcode = '42501';
      end if;
    end if;

    -- Peer verification is counted by the verifications trigger, never by hand.
    if new.verification_count is distinct from old.verification_count
       or new.verified_at is distinct from old.verified_at
       or new.auto_validated is distinct from old.auto_validated
       or (new.status = 'verified' and old.status <> 'verified') then
      if r <> 'admin' then
        raise exception 'Reports are verified by peer confirmations' using errcode = '42501';
      end if;
    end if;

    if workflow_changed then
      if r not in ('ewv', 'ewr', 'ldp_coordinator', 'project_staff', 'admin') then
        raise exception 'Your role cannot approve, reject or reopen reports' using errcode = '42501';
      end if;
      if r <> 'admin' and old.user_id = auth.uid() then
        raise exception 'You cannot approve or reject your own report' using errcode = '42501';
      end if;
    end if;
  end if;

  -- Keep decision columns consistent with the status, whoever wrote it.
  if new.status is distinct from old.status then
    case new.status
      when 'approved' then
        new.approved_at := coalesce(new.approved_at, now());
        new.rejected_at := null;
        new.rejection_reason := null;
      when 'rejected' then
        new.rejected_at := coalesce(new.rejected_at, now());
        new.approved_at := null;
      when 'verified' then
        new.verified_at := coalesce(new.verified_at, now());
        new.approved_at := null;
        new.rejected_at := null;
        new.rejection_reason := null;
      else
        null;
    end case;
  end if;

  new.is_alert := new.severity in ('high', 'critical');
  return new;
end $$;

-- ── Reopen only reports that have left 'pending' ────────────────────────────
create or replace function public.reopen_report(p_report_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  r text := public.app_role();
  owner uuid;
  cur text;
begin
  if r not in ('ewv', 'ewr', 'ldp_coordinator', 'project_staff', 'admin') then
    raise exception 'Your role cannot reopen reports' using errcode = '42501';
  end if;

  select user_id, status into owner, cur from reports where id = p_report_id for update;
  if not found then
    raise exception 'Report not found' using errcode = 'P0002';
  end if;
  if cur = 'pending' then
    raise exception 'Report is already pending' using errcode = '22023';
  end if;
  if r <> 'admin' and owner = auth.uid() then
    raise exception 'You cannot reopen your own report' using errcode = '42501';
  end if;

  perform set_config('cradi.trusted_write', 'on', true);

  delete from verifications where report_id = p_report_id;

  update reports
     set status = 'pending',
         verification_count = 0,
         verified_at = null,
         auto_validated = false,
         approved_at = null,
         rejected_at = null,
         rejection_reason = null,
         escalated = false,
         escalated_at = null,
         escalation_reason = null,
         escalation_scheduled_at =
           now() + make_interval(mins => public.setting_int('escalation_timeout_minutes', 30)),
         escalation_status = 'pending',
         updated_by = auth.uid()
   where id = p_report_id;

  update scheduled_escalations
     set status = 'skipped', reason = 'Report reopened', processed_at = now()
   where report_id = p_report_id and status = 'pending';

  insert into scheduled_escalations (report_id, escalate_at)
    select id, escalation_scheduled_at from reports where id = p_report_id;

  -- Events queued before the reopen describe the old votes / decision.
  update notification_outbox
     set processed_at = now(), last_error = 'superseded by reopen'
   where processed_at is null
     and event_type in ('report_disputed', 'report_created', 'report_status_changed')
     and payload ->> 'report_id' = p_report_id::text;

  insert into notification_outbox (event_type, payload)
    values ('report_created', jsonb_build_object('report_id', p_report_id, 'reopened', true));

  perform set_config('cradi.trusted_write', '', true);
end $$;

-- ── Audit admin 'verified' decisions too ────────────────────────────────────
create or replace function public.reports_audit_decision()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null
     and pg_trigger_depth() = 1          -- a direct decision, not the peer-vote trigger
     and new.status is distinct from old.status
     and new.status in ('approved', 'rejected', 'verified') then
    insert into verification_overrides (report_id, validator_id, action, reason)
      values (new.id, auth.uid(), new.status, coalesce(new.rejection_reason, ''));
  end if;
  return new;
end $$;

-- ── Votes only on pending reports; recount on admin edits ───────────────────
create or replace function public.report_status(p_report_id uuid)
returns text language sql stable security definer set search_path = public as $$
  select status from reports where id = p_report_id
$$;

revoke execute on function public.report_status(uuid) from public, anon;
grant execute on function public.report_status(uuid) to authenticated, service_role;

drop policy verifications_insert on public.verifications;
create policy verifications_insert on public.verifications for insert to authenticated
  with check (
    verifier_id = auth.uid()
    and public.is_verifier()
    and public.report_status(report_id) = 'pending'
    and public.report_owner(report_id) is distinct from auth.uid()
    and (public.app_role() <> 'ewm'
         or (public.report_ward(report_id) = public.my_ward()
             and public.report_lga(report_id) = public.my_lga()))
  );

create or replace function public.verifications_after_update()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform 1 from reports where id = new.report_id for update;
  update reports
     set verification_count = (select count(*) from verifications
                                where report_id = new.report_id and is_confirmed)
   where id = new.report_id;
  return new;
end $$;

create trigger verifications_after_update after update of is_confirmed on public.verifications
  for each row execute function public.verifications_after_update();


-- ============================================================================
-- SOURCE: supabase/migrations/20260927000000_security_hardening.sql
-- ============================================================================

-- Security and consistency hardening from the security / logic audits:
--  * chat only for approved, enabled users; sender_name set server-side;
--    per-user message rate limit
--  * report insert rate limit and field length caps; reporter_name and
--    workflow columns always server-controlled on insert
--  * report-images objects can't be overwritten (evidence) and only admins
--    delete them
--  * profiles visibility narrowed (EWMs see only same-area peers)
--  * report lookup helpers reveal nothing about reports the caller can't see
--  * alerts attributed to their real author; audit rows trigger-only
--  * vote edits apply the threshold; vote deletes lock the report; reopen
--    no longer supersedes its own 'back to pending' event
--  * guard also protects reporter_name, created_at, legacy id, synced_at and
--    escalation columns; forces updated_by; location frozen after any vote

-- ── helpers ─────────────────────────────────────────────────────────────────
create or replace function public.is_approved_user()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select is_approved and not is_disabled from profiles where id = auth.uid()), false)
$$;

create or replace function public.report_has_votes(p_report_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from verifications where report_id = p_report_id)
$$;

-- Report lookups used by RLS policies: only answer for reports the caller
-- may already see (reporter or staff), so they can't be used as an oracle.
create or replace function public.can_see_report_meta(p_report_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_staff()
      or exists (select 1 from reports where id = p_report_id and user_id = auth.uid())
$$;

create or replace function public.report_owner(p_report_id uuid)
returns uuid language sql stable security definer set search_path = public as $$
  select user_id from reports where id = p_report_id and public.can_see_report_meta(p_report_id)
$$;

create or replace function public.report_ward(p_report_id uuid)
returns text language sql stable security definer set search_path = public as $$
  select ward from reports where id = p_report_id and public.can_see_report_meta(p_report_id)
$$;

create or replace function public.report_lga(p_report_id uuid)
returns text language sql stable security definer set search_path = public as $$
  select lga from reports where id = p_report_id and public.can_see_report_meta(p_report_id)
$$;

create or replace function public.report_status(p_report_id uuid)
returns text language sql stable security definer set search_path = public as $$
  select status from reports where id = p_report_id and public.can_see_report_meta(p_report_id)
$$;

create or replace function public.auth_user_confirmed(p_user_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select case when p_user_id = auth.uid() or public.is_admin() then exists (
    select 1 from auth.users u
     where u.id = p_user_id
       and (u.email_confirmed_at is not null or u.phone_confirmed_at is not null))
  else false end
$$;

revoke execute on function public.is_approved_user(), public.report_has_votes(uuid),
  public.can_see_report_meta(uuid) from public, anon;
grant execute on function public.is_approved_user(), public.report_has_votes(uuid),
  public.can_see_report_meta(uuid) to authenticated, service_role;

-- ── chat ────────────────────────────────────────────────────────────────────
drop policy messages_select on public.messages;
create policy messages_select on public.messages for select to authenticated
  using (public.is_approved_user());

drop policy messages_insert on public.messages;
create policy messages_insert on public.messages for insert to authenticated
  with check (sender_id = auth.uid() and public.is_approved_user());

create or replace function public.messages_before_write()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    if auth.uid() is not null and (
         select count(*) from messages
          where sender_id = auth.uid() and created_at > now() - interval '1 minute') >= 30 then
      raise exception 'You are sending messages too quickly' using errcode = '54000';
    end if;
    select coalesce(nullif(name, ''), 'User') into new.sender_name
      from profiles where id = new.sender_id;
    new.message := left(new.message, 2000);
  else
    new.sender_name := old.sender_name;
    new.sender_id := old.sender_id;
    new.message := left(new.message, 2000);
  end if;
  return new;
end $$;

create trigger messages_before_write before insert or update on public.messages
  for each row execute function public.messages_before_write();

-- ── reports: insert hardening ───────────────────────────────────────────────
alter table public.reports
  add constraint reports_hazard_type_len check (char_length(hazard_type) between 1 and 60),
  add constraint reports_description_len check (char_length(description) <= 2000),
  add constraint reports_location_len check (
    char_length(location_details) <= 500 and char_length(location) <= 500
    and char_length(address) <= 500 and char_length(ward) <= 120
    and char_length(lga) <= 120 and char_length(state) <= 120),
  add constraint reports_image_urls_count check (coalesce(array_length(image_urls, 1), 0) <= 10);

create or replace function public.reports_before_insert()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null then
    -- Client inserts: workflow / attribution columns are server-controlled.
    if (select count(*) from reports
         where user_id = auth.uid() and created_at > now() - interval '1 hour') >= 20 then
      raise exception 'Too many reports submitted in the last hour. Please try again later.'
        using errcode = '54000';
    end if;
    new.reporter_name := null;
    new.verification_count := 0;
    new.verified_at := null;
    new.auto_validated := false;
    new.approved_at := null;
    new.rejected_at := null;
    new.rejection_reason := null;
    new.escalated := false;
    new.escalated_at := null;
    new.escalation_reason := null;
    new.legacy_firebase_id := null;
    new.updated_by := null;
    new.created_at := now();
  end if;
  if new.reporter_name is null and new.user_id is not null then
    select name into new.reporter_name from profiles where id = new.user_id;
  end if;
  new.is_alert := new.severity in ('high', 'critical');
  if new.status = 'pending' then
    new.escalation_scheduled_at :=
      now() + make_interval(mins => public.setting_int('escalation_timeout_minutes', 30));
    new.escalation_status := 'pending';
  end if;
  return new;
end $$;

-- ── reports: update guard (final definition) ────────────────────────────────
create or replace function public.guard_report_update()
returns trigger language plpgsql as $$
declare
  r text;
  workflow_changed boolean;
  content_changed boolean;
  location_changed boolean;
begin
  if auth.uid() is not null and pg_trigger_depth() = 1
     and not public.guard_report_update_trusted() then
    r := public.app_role();
    new.updated_by := auth.uid();

    if new.status = 'pending' and old.status is distinct from 'pending' then
      raise exception 'Use reopen_report() to move a report back to pending'
        using errcode = '42501';
    end if;

    workflow_changed :=
         new.status is distinct from old.status
      or new.approved_at is distinct from old.approved_at
      or new.rejected_at is distinct from old.rejected_at
      or new.rejection_reason is distinct from old.rejection_reason;

    location_changed :=
         new.ward is distinct from old.ward
      or new.lga is distinct from old.lga
      or new.state is distinct from old.state
      or new.latitude is distinct from old.latitude
      or new.longitude is distinct from old.longitude;

    content_changed := location_changed
      or new.hazard_type is distinct from old.hazard_type
      or new.severity is distinct from old.severity
      or new.description is distinct from old.description
      or new.location_details is distinct from old.location_details
      or new.location is distinct from old.location
      or new.address is distinct from old.address
      or new.image_urls is distinct from old.image_urls
      or new.submitted_at is distinct from old.submitted_at
      or new.type is distinct from old.type
      or new.reporter_name is distinct from old.reporter_name
      or new.created_at is distinct from old.created_at
      or new.legacy_firebase_id is distinct from old.legacy_firebase_id
      or new.synced_at is distinct from old.synced_at;

    if content_changed and r <> 'admin' then
      if old.user_id is distinct from auth.uid() then
        raise exception 'Only the reporter can edit a report''s details' using errcode = '42501';
      end if;
      if location_changed and public.report_has_votes(old.id) then
        raise exception 'The location cannot change after peers have verified the report'
          using errcode = '42501';
      end if;
    end if;

    if new.user_id is distinct from old.user_id
       or new.escalated is distinct from old.escalated
       or new.escalation_status is distinct from old.escalation_status
       or new.escalated_at is distinct from old.escalated_at
       or new.escalation_reason is distinct from old.escalation_reason
       or new.escalation_scheduled_at is distinct from old.escalation_scheduled_at then
      if r <> 'admin' then
        raise exception 'Only an admin can change report ownership or escalation'
          using errcode = '42501';
      end if;
    end if;

    -- Peer verification is counted by the verifications trigger, never by hand.
    if new.verification_count is distinct from old.verification_count
       or new.verified_at is distinct from old.verified_at
       or new.auto_validated is distinct from old.auto_validated
       or (new.status = 'verified' and old.status <> 'verified') then
      if r <> 'admin' then
        raise exception 'Reports are verified by peer confirmations' using errcode = '42501';
      end if;
    end if;

    if workflow_changed then
      if r not in ('ewv', 'ewr', 'ldp_coordinator', 'project_staff', 'admin') then
        raise exception 'Your role cannot approve, reject or reopen reports' using errcode = '42501';
      end if;
      if r <> 'admin' and old.user_id = auth.uid() then
        raise exception 'You cannot approve or reject your own report' using errcode = '42501';
      end if;
    end if;
  end if;

  -- Keep decision columns consistent with the status, whoever wrote it.
  if new.status is distinct from old.status then
    case new.status
      when 'approved' then
        new.approved_at := coalesce(new.approved_at, now());
        new.rejected_at := null;
        new.rejection_reason := null;
      when 'rejected' then
        new.rejected_at := coalesce(new.rejected_at, now());
        new.approved_at := null;
      when 'verified' then
        new.verified_at := coalesce(new.verified_at, now());
        new.approved_at := null;
        new.rejected_at := null;
        new.rejection_reason := null;
      else
        null;
    end case;
  end if;

  new.is_alert := new.severity in ('high', 'critical');
  return new;
end $$;

-- ── reopen: don't supersede its own events (final definition) ───────────────
create or replace function public.reopen_report(p_report_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  r text := public.app_role();
  owner uuid;
  cur text;
  v_last_event bigint;
begin
  if r not in ('ewv', 'ewr', 'ldp_coordinator', 'project_staff', 'admin') then
    raise exception 'Your role cannot reopen reports' using errcode = '42501';
  end if;

  select user_id, status into owner, cur from reports where id = p_report_id for update;
  if not found then
    raise exception 'Report not found' using errcode = 'P0002';
  end if;
  if cur = 'pending' then
    raise exception 'Report is already pending' using errcode = '22023';
  end if;
  if r <> 'admin' and owner = auth.uid() then
    raise exception 'You cannot reopen your own report' using errcode = '42501';
  end if;

  select coalesce(max(id), 0) into v_last_event from notification_outbox;

  perform set_config('cradi.trusted_write', 'on', true);

  delete from verifications where report_id = p_report_id;

  update reports
     set status = 'pending',
         verification_count = 0,
         verified_at = null,
         auto_validated = false,
         approved_at = null,
         rejected_at = null,
         rejection_reason = null,
         escalated = false,
         escalated_at = null,
         escalation_reason = null,
         escalation_scheduled_at =
           now() + make_interval(mins => public.setting_int('escalation_timeout_minutes', 30)),
         escalation_status = 'pending',
         updated_by = auth.uid()
   where id = p_report_id;

  update scheduled_escalations
     set status = 'skipped', reason = 'Report reopened', processed_at = now()
   where report_id = p_report_id and status = 'pending';

  insert into scheduled_escalations (report_id, escalate_at)
    select id, escalation_scheduled_at from reports where id = p_report_id;

  -- Events queued before the reopen describe the old votes / decision.
  update notification_outbox
     set processed_at = now(), last_error = 'superseded by reopen'
   where processed_at is null
     and id <= v_last_event
     and event_type in ('report_disputed', 'report_created', 'report_status_changed')
     and payload ->> 'report_id' = p_report_id::text;

  insert into notification_outbox (event_type, payload)
    values ('report_created', jsonb_build_object('report_id', p_report_id, 'reopened', true));

  perform set_config('cradi.trusted_write', '', true);
end $$;

-- ── votes: edits apply the threshold; deletes lock the report ───────────────
create or replace function public.verifications_after_update()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  confirmed int;
begin
  perform 1 from reports where id = new.report_id for update;
  select count(*) into confirmed
    from verifications where report_id = new.report_id and is_confirmed;
  update reports set verification_count = confirmed where id = new.report_id;
  if confirmed >= public.setting_int('minimum_peer_confirmations', 2) then
    update reports
       set status = 'verified', verified_at = now(), auto_validated = true
     where id = new.report_id and status = 'pending';
  end if;
  return new;
end $$;

create or replace function public.verifications_after_delete()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform 1 from reports where id = old.report_id for update;
  update reports
     set verification_count = (select count(*) from verifications
                                where report_id = old.report_id and is_confirmed)
   where id = old.report_id;
  return old;
end $$;

-- ── profiles visibility ─────────────────────────────────────────────────────
drop policy profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated
  using (
    id = auth.uid()
    or public.app_role() in ('admin', 'ldp_coordinator', 'project_staff', 'ewv', 'ewr')
    or (public.app_role() = 'ewm'
        and ward = public.my_ward() and lga = public.my_lga())
  );

-- ── alerts attribution; audit rows trigger-only ─────────────────────────────
drop policy alerts_write on public.alerts;
create policy alerts_insert on public.alerts for insert to authenticated
  with check (
    public.app_role() in ('ewv', 'ewr', 'ldp_coordinator', 'project_staff', 'admin', 'techSupport')
    and created_by = auth.uid()
  );
create policy alerts_update on public.alerts for update to authenticated
  using (public.app_role() in ('ewv', 'ewr', 'ldp_coordinator', 'project_staff', 'admin', 'techSupport'))
  with check (public.app_role() in ('ewv', 'ewr', 'ldp_coordinator', 'project_staff', 'admin', 'techSupport'));
create policy alerts_delete on public.alerts for delete to authenticated
  using (public.app_role() in ('ewv', 'ewr', 'ldp_coordinator', 'project_staff', 'admin', 'techSupport'));

create or replace function public.alerts_guard_author()
returns trigger language plpgsql as $$
begin
  if auth.uid() is not null and new.created_by is distinct from old.created_by then
    raise exception 'The author of an alert cannot be changed' using errcode = '42501';
  end if;
  return new;
end $$;

create trigger alerts_guard_author before update on public.alerts
  for each row execute function public.alerts_guard_author();

drop policy verification_overrides_insert on public.verification_overrides;

-- ── evidence images can't be overwritten; only admins delete them ───────────
drop policy "users update own images" on storage.objects;
create policy "users update own profile images" on storage.objects for update to authenticated
  using (bucket_id = 'profile-images' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy "users delete own images" on storage.objects;
create policy "users delete own profile images" on storage.objects for delete to authenticated
  using (
    (bucket_id = 'profile-images' and (storage.foldername(name))[1] = auth.uid()::text)
    or (bucket_id in ('report-images', 'profile-images') and public.is_admin())
  );


-- ============================================================================
-- SOURCE: supabase/migrations/20260927010000_approval_confirmed_and_sync_retry.sql
-- ============================================================================

-- 1. An account can only be approved once its email/phone is confirmed, for
--    every approval path (web admin API, mobile admin screen, SQL by an admin
--    user). Stops approving a sign-up made with someone else's address.
-- 2. The report rate limit ignores retries of a report that already exists
--    (offline sync re-sending an upsert), so they aren't refused.

create or replace function public.guard_profile_approval()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.is_approved and not coalesce(old.is_approved, false) and not exists (
       select 1 from auth.users u
        where u.id = new.id
          and (u.email_confirmed_at is not null or u.phone_confirmed_at is not null)) then
    raise exception 'This account has not confirmed its email or phone yet, so it cannot be approved'
      using errcode = '42501';
  end if;
  return new;
end $$;

create trigger profiles_guard_approval before update of is_approved on public.profiles
  for each row execute function public.guard_profile_approval();

create or replace function public.reports_before_insert()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null then
    -- Client inserts: workflow / attribution columns are server-controlled.
    -- A retry of an already-stored report (offline sync upsert) is not a new
    -- submission, so it doesn't count toward the hourly limit.
    if not exists (select 1 from reports where id = new.id)
       and (select count(*) from reports
             where user_id = auth.uid() and created_at > now() - interval '1 hour') >= 20 then
      raise exception 'Too many reports submitted in the last hour. Please try again later.'
        using errcode = '54000';
    end if;
    new.reporter_name := null;
    new.verification_count := 0;
    new.verified_at := null;
    new.auto_validated := false;
    new.approved_at := null;
    new.rejected_at := null;
    new.rejection_reason := null;
    new.escalated := false;
    new.escalated_at := null;
    new.escalation_reason := null;
    new.legacy_firebase_id := null;
    new.updated_by := null;
    new.created_at := now();
  end if;
  if new.reporter_name is null and new.user_id is not null then
    select name into new.reporter_name from profiles where id = new.user_id;
  end if;
  new.is_alert := new.severity in ('high', 'critical');
  if new.status = 'pending' then
    new.escalation_scheduled_at :=
      now() + make_interval(mins => public.setting_int('escalation_timeout_minutes', 30));
    new.escalation_status := 'pending';
  end if;
  return new;
end $$;


-- ============================================================================
-- SOURCE: supabase/migrations/20260927020000_access_sync_and_settings_cleanup.sql
-- ============================================================================

-- 1. Blocking/unblocking a user (profiles.is_disabled) from ANY path — web
--    admin API, mobile admin screen, SQL — queues 'user_access_changed'; the
--    Railway backend then applies/lifts the Supabase Auth ban so sign-in
--    matches the flag.
-- 2. Remove app_settings keys nothing reads (they would only confuse the
--    admin settings page).

create or replace function public.profiles_after_access_change()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.is_disabled is distinct from old.is_disabled then
    insert into notification_outbox (event_type, payload)
      values ('user_access_changed', jsonb_build_object('user_id', new.id));
  end if;
  return new;
end $$;

create trigger profiles_after_access_change after update of is_disabled on public.profiles
  for each row execute function public.profiles_after_access_change();

delete from public.app_settings
 where key in ('sms_dedup_window_minutes', 'content_cache_ttl_hours',
               'max_report_image_mb', 'feature_flag_voice_reports');


-- ============================================================================
-- SOURCE: supabase/migrations/20260927030000_authorities_coverage_state.sql
-- ============================================================================

-- LGA names repeat across states (e.g. Obi in Benue and in Nasarawa), so SMS
-- recipients also record the state they cover. The admin panel sets it for new
-- and edited rows, and the backend matches (lga, state).
--
-- SUPERSEDED by 20260927090000: this migration left coverage_state nullable,
-- and a row with NULL was matched by LGA name alone — so a contact for one of
-- the 6 ambiguous names (Bassa, Ifelodun, Irepodun, Nasarawa, Obi, Surulere)
-- was texted about incidents in both of its states. 20260927090000 resolves or
-- quarantines those rows and makes the column NOT NULL with foreign keys into
-- public.nigeria_states / public.nigeria_lgas. Nothing nullable survives.

alter table public.authorities add column coverage_state text;

create index authorities_lga_state_idx on public.authorities (coverage_lga, coverage_state);


-- ============================================================================
-- SOURCE: supabase/migrations/20260927040000_builtin_content.sql
-- ============================================================================

-- Built-in content moves out of the app and into the database, where admins
-- manage it (web admin: Knowledge Base, News Links, Settings):
-- 1. The 10 safety guides the app used to bundle are seeded into
--    knowledge_base (the placeholder SEMA phone number is replaced with
--    advice to call 112; admins can add the real SEMA number here).
-- 2. news_links: curated links the app shows when the live ReliefWeb feed is
--    unavailable (previously hard-coded, one with a dead '#' link).
-- 3. support_email setting (previously hard-coded in the Help screen).
-- Seed rows use fixed ids (on conflict do nothing), so admin edits to them are
-- never overwritten by a re-seed.

insert into public.knowledge_base (id, title, content, source, category, hazard_type, image_url) values
  ('a5fd2620-6d5a-5d98-a0fd-5877944ab528', 'River Benue Flooding Protocols', $seed$**Early Warning Indicators:**
• Heavy rainfall reports from upstream regions (Cameroon/Lagdo Dam releases).
• Unusual rise in River Benue and local tributaries.
• Flash-flood alerts via CRADI app or local authorities.

**Before a Flood:**
• Move valuables, livestock, and essential documents to higher ground or designated secure community centers.
• Prepare an emergency Go-Bag with 3 days of water, non-perishable food, and a battery/solar radio.
• Identify the nearest high-ground community evacuation route (avoiding known washout zones).
• Secure your crops if possible and clear local drainage channels.

**During a Flood:**
• Evacuate IMMEDIATELY to higher ground when ordered by SEMA or the State Emergency Response Team.
• NEVER walk, swim, or drive through floodwaters (6 inches of moving water can sweep a person away).
• Listen exclusively to official local broadcasts (Radio Benue, Joy FM) or CRADI alerts.
• Stay entirely clear of downed power lines and transformers.

**Emergency Contacts:**
• National Emergency Toll-Free: 112
• Your State Emergency Management Agency (SEMA): call 112 and ask to be connected, or use the number announced on local radio
• NEMA North Central Office: Jos, Plateau State$seed$, 'Benue SEMA / NEMA', 'Flood', 'flood', 'https://images.unsplash.com/photo-1504701954957-2010ec3bcec1?auto=format&fit=crop&q=80&w=800'),
  ('fa566a96-2090-5ac6-af78-034f16d23451', 'Gully Erosion Mitigation (Nasarawa/Plateau Context)', $seed$**Recognizing Erosion Threats:**
• Sudden cracks appearing in community roads or near building foundations.
• Rapid widening of existing gullies after heavy seasonal rains.
• Exposed tree roots or leaning utility poles along embankments.

**Preventative Measures (Dry Season):**
• Plant deep-rooted native grasses (like Vetiver grass) and bamboo along vulnerable slopes to bind the soil.
• Construct community sandbag barriers or stone-pitching at the head of advancing gullies.
• Do NOT dump refuse in erosion channels or natural waterways; this blocks flow and destroys banks.
• Practice terraced farming on hillsides (especially in Plateau State) to reduce water runoff speed.

**Emergency Response (Heavy Rains):**
• Keep children and livestock completely away from gully edges (banks can collapse without warning).
• If a building is threatened, evacuate immediately and notify local authorities via the CRADI app.
• Do not attempt to cross flooded gullies during rainstorms.

**Where to Report:**
• Report expanding gullies immediately via CRADI to alert NEWMAP (Nigeria Erosion and Watershed Management Project) and local works ministries.$seed$, 'NEMA / NEWMAP', 'Erosion', 'erosion', 'https://images.unsplash.com/photo-1509316785289-025f5b846b35?auto=format&fit=crop&q=80&w=800'),
  ('51ea6c2c-ce4a-5be3-91ec-1c327add7ab9', 'Extreme Heat Survival (Makurdi/Lafia Corridors)', $seed$**Understanding the Threat:**
• Extended dry seasons with temperatures routinely exceeding 38°C (100°F).
• High risk of heatstroke for outdoor workers, farmers, and the elderly.

**Safety Protocols:**
• **Hydration:** Drink plenty of clean water constantly, even if you do not feel thirsty. Avoid excessive sugary or alcoholic drinks.
• **Shelter:** Seek shade during peak sun hours (11:00 AM to 4:00 PM). Ensure good cross-ventilation in homes.
• **Clothing:** Wear loose-fitting, light-colored cotton clothing to reflect heat.
• **Farming Adjustments:** Shift heavy labor to early morning (before 10 AM) or late afternoon.

**Recognizing Heatstroke:**
• Symptoms: High body temperature, hot/dry/red skin, rapid pulse, dizziness, nausea, or confusion.
• **Action:** This is a medical emergency. Move the person to shade immediately, actively cool them with wet cloths, and transport to the nearest Primary Healthcare Center (PHC).

**Livestock Care:**
• Provide natural shade structures or planting trees for livestock.
• Ensure constant access to clean, cool drinking water for all animals to prevent mass dehydration.$seed$, 'Federal Ministry of Health / NiMet', 'Extreme Heat', 'extreme_heat', 'https://images.unsplash.com/photo-1504192010706-dd7f569ee2be?auto=format&fit=crop&q=80&w=800'),
  ('074a4313-796f-5902-8a45-fc30b9487bff', 'Bush Fire & Urban Fire Response', $seed$**Prevention & Preparedness:**
• Avoid indiscriminate bush burning (slash-and-burn agriculture) during the peak dry season or Harmattan.
• Create firebreaks (cleared pathways of at least 10 meters) around farms and vulnerable settlements.
• Keep fire extinguishers accessible in urban homes, and never leave cooking gas or firewood unattended.
• Do not discard cigarette butts or glass bottles in dry grass.

**During a Fire:**
• Evacuate upwind of the fire immediately. Do not attempt to outrun a fast-moving fire uphill.
• In an urban building fire, crawl low under the smoke where the air is cleaner.
• Use the CRADI app to alert the community and deploy the local emergency response volunteer network.
• If trapped in bush, find a cleared area or water body, lie flat, and cover your mouth with a wet cloth to filter smoke.

**Post-Fire Recovery:**
• Do not return until local authorities declare the area totally clear of smoldering hazards.
• Watch for "hot spots" that can flare up with wind.
• Protect respiratory health from lingering smoke by wearing masks (N95 or heavy cloth).$seed$, 'Federal Fire Service', 'Fire', 'fire', 'https://images.unsplash.com/photo-1516912481808-3406841bd33c?auto=format&fit=crop&q=80&w=800'),
  ('1f5190b6-576b-5f2b-8be9-4779fc4d400f', 'Communal Conflict & Security Preparedness (Middle Belt Context)', $seed$**Early Warning Indicators:**
• Reports of stolen livestock, destroyed crops, or violent skirmishes in neighboring communities.
• Unusual mass movement of nomadic groups or sudden influx of displaced persons.
• Circulation of inflammatory messages, hate speech, or unverified rumors on social media or local gatherings.
• Sudden withdrawal of ethnic or religious groups from shared markets.

**Preparedness & Prevention:**
• Engage continuously with local Peace and Reconciliation Committees (PRCs) and inter-faith dialogue groups.
• Avoid sharing unverified provocative images or voice notes (fake news). Verify information through community leaders or the CRADI app.
• Identify safe havens (e.g., heavily guarded central zones, designated religious grounds, or police compounds).
• Keep emergency contacts of local vigilante commanders, police DPOs, and military task force units handy.

**During an Outbreak of Violence:**
• Secure your family indoors if the threat is external, or evacuate immediately to pre-identified safe havens if your area is directly targeted.
• Avoid nighttime travel entirely. Stick to major, well-patrolled roads if movement is absolutely necessary.
• Report ongoing attacks immediately via the CRADI app so that EWER networks can alert joint military and police task forces.

**Post-Conflict Protocol:**
• Do not engage in retaliatory attacks; this perpetuates the cycle of violence.
• Assist IDPs (Internally Displaced Persons) with basic needs and report their numbers to SEMA for relief coordination.
• Cooperate fully with security agencies and human rights monitors gathering evidence.$seed$, 'Institute for Peace and Conflict Resolution (IPCR)', 'Conflict', 'conflict', 'https://images.unsplash.com/photo-1599059813005-11265ba4b4ce?auto=format&fit=crop&q=80&w=800'),
  ('c83d5158-6dbc-5773-be9c-64cca9069dc2', 'Road Traffic & Industrial Accident Response', $seed$**Road Traffic Accidents (RTA):**
• **Secure the Scene:** Park your vehicle at a safe distance with hazard lights on. Put out reflective warning triangles at least 50 meters behind the accident to warn oncoming traffic.
• **Assessment:** Check if victims are responsive. Do NOT move a severely injured person (especially neck/back injuries) unless there is immediate danger of fire or explosion.
• **Alerting:** Use the CRADI app to call the Federal Road Safety Corps (FRSC) (Toll-free: 122) and nearby medical emergency services.
• **First Aid:** Administer CPR only if trained. Use clean cloth to apply firm, direct pressure to severely bleeding wounds.

**Industrial & Farming Accidents:**
• **Machine Entanglement:** Immediately shut off the power source. Do not attempt to reverse the machinery unless trained to do so safely.
• **Chemical Spills (Agrochemicals/Pesticides):** Evacuate the immediate area. If chemicals contact the skin or eyes, flush continuously with clean water for at least 15 minutes. Remove contaminated clothing. Seek medical help immediately.
• **Falls from Height:** Do not move the victim. Keep them warm and wait for emergency medical transport.

**General Safety Rule:**
Always carry a well-stocked First Aid kit in your vehicle and on large farming sites. Document the incident details safely for police and insurance reports.$seed$, 'Federal Road Safety Corps (FRSC)', 'Accident', 'accident', 'https://images.unsplash.com/photo-1544636331-e26879cd4d9b?auto=format&fit=crop&q=80&w=800'),
  ('d8539b52-b279-5fd6-94b3-16d5d4ba68b9', 'Storm & Severe Weather Safety', $seed$**Before a Storm:**
• Monitor weather forecasts and warnings
• Prepare emergency kit: water, non-perishable food, flashlight, battery radio
• Charge phones and backup power banks
• Secure outdoor objects that could blow away
• Know your evacuation routes
• Trim trees and branches near buildings

**During Thunderstorms:**
• Go indoors to a sturdy building
• Avoid windows and doors
• Unplug electronics
• Do not use corded phones
• Stay away from plumbing and running water
• If outdoors: avoid tall objects, seek low ground

**During High Winds:**
• Stay indoors away from windows
• Close all interior doors
• Go to an interior room on the lowest floor
• If in vehicle: park safely and stay inside

**After the Storm:**
• Wait for official all-clear
• Watch for fallen power lines
• Avoid flooded areas
• Document damage for insurance
• Use flashlights, not candles
• Check on neighbors, especially elderly$seed$, 'NOAA/FEMA', 'Storm', 'storm', 'https://images.unsplash.com/photo-1535350356005-fd52b3b524fb?auto=format&fit=crop&q=80&w=800'),
  ('6dc6401f-e70a-5650-92c7-34d8a5a9a54f', 'Earthquake Preparedness & Response', $seed$**Before an Earthquake:**
• Secure heavy furniture and appliances to walls
• Store heavy items on lower shelves
• Identify safe spots in each room (under sturdy furniture, against interior walls)
• Prepare emergency kit with supplies for 72 hours
• Practice "Drop, Cover, and Hold On" drills
• Know how to turn off utilities (gas, water, electricity)

**During an Earthquake:**
• DROP to hands and knees
• take COVER under sturdy furniture
• HOLD ON until shaking stops
• If indoors: stay inside, away from windows
• If outdoors: move to open area away from buildings
• If in vehicle: pull over and stay inside
• DO NOT run outside or stand in doorways

**After an Earthquake:**
• Check yourself and others for injuries
• Inspect home for damage
• Expect aftershocks
• Turn off gas if you smell or hear leaking
• Use SMS instead of phone calls
• Stay away from damaged buildings
• Listen to emergency broadcasts
• Help neighbors who may need assistance
• Move inland and to higher ground immediately if near coast$seed$, 'FEMA/USGS', 'Earthquake', 'earthquake', 'https://images.unsplash.com/photo-1548337138-e87d889cc369?auto=format&fit=crop&q=80&w=800'),
  ('f4bb8a6f-db2f-5107-ae3c-e5f5bb1a53fc', 'Epidemic & Disease Outbreak Response', $seed$**Prevention & Preparedness:**
• Stay informed through official health sources (NCDC, WHO).
• Practice good hygiene: wash hands frequently (20 seconds with soap) and use sanitizer.
• Maintain clean living environment. Dispose of refuse properly to prevent cholera and malaria vectors.
• Keep vaccinations up to date (yellow fever, meningitis, measles, etc.).
• Stock 30-day supply of personal medications.

**During an Outbreak:**
• Follow official Nigeria Centre for Disease Control (NCDC) guidelines.
• Maintain social distancing as advised.
• Wear masks if recommended by health authorities (especially for respiratory diseases like COVID-19 or Lassa fever prevention).
• Store food securely in rat-proof containers to prevent Lassa Fever transmission.
• Avoid touching face with unwashed hands and disinfect frequently-touched surfaces.

**If You Get Sick:**
• Isolate yourself from others in household.
• Stay home except to get medical care.
• Wear a mask when around others and cover coughs/sneezes.
• Seek prompt medical attention, especially for high fever or severe symptoms. Do not rely entirely on self-medication.
• Notify close contacts.

**Community Protection:**
• Support vulnerable populations (elderly, immunocompromised).
• Combat misinformation and share only official NCDC updates.
• Report clusters of unusual sickness in the community via the CRADI app.$seed$, 'NCDC / WHO', 'Disease', 'disease', 'https://images.unsplash.com/photo-1588681664899-f142ff2dc9b1?auto=format&fit=crop&q=80&w=800'),
  ('a538ef91-3b9b-565e-b903-49e9150b1f7a', 'General Safety & Emergency Kit Essentials', $seed$**Basic Emergency Supply Kit:**

**Water & Food:**
• 1 gallon of water per person per day (3-day supply)
• Non-perishable food (3-day supply, e.g., garri, canned beans, groundnuts)
• Manual can opener
• Baby formula and food (if applicable)

**First Aid:**
• First aid kit (bandages, antiseptic wipes, iodine)
• Prescription medications (7-day supply)
• Over-the-counter medications (pain relievers, anti-diarrhea, anti-malaria)
• Medical equipment (hearing aids, glasses)

**Tools & Supplies:**
• Battery-powered or hand-crank radio (NOAA or local stations)
• Flashlight with extra batteries (or fully charged solar torch)
• Whistle (to signal for help)
• Moist towelettes, garbage bags for sanitation
• Basic tools to turn off utilities.

**Documents & Money:**
• Copies of important documents (ID cards, insurance policies, land titles). Store in a waterproof container or ziplock bag.
• Emergency cash (small denominations as ATMs may not work during crises).

**Communication:**
• Charged cell phone with chargers and backup power bank.
• Emergency contact list written on paper.
 
**Stay vigilant:**
Always have an evacuation plan and discuss it with your household members regularly.$seed$, 'FEMA / Red Cross / SEMA', 'Safety', 'safety', 'https://images.unsplash.com/photo-1496247749665-49cf5b1022e9?auto=format&fit=crop&q=80&w=800')
on conflict (id) do nothing;

create table public.news_links (
  id          uuid primary key default gen_random_uuid(),
  title       text not null check (length(btrim(title)) between 1 and 300),
  url         text not null check (url ~* '^https?://[^[:space:]]+$' and length(url) <= 2000),
  source      text not null default '' check (length(source) <= 120),
  sort_order  int not null default 0,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index news_links_order_idx on public.news_links (sort_order, created_at);

create trigger news_links_touch before update on public.news_links
  for each row execute function public.touch_updated_at();

alter table public.news_links enable row level security;

create policy news_links_select on public.news_links for select to authenticated
  using (is_active or public.app_role() in ('admin', 'techSupport'));

create policy news_links_write on public.news_links for all to authenticated
  using (public.app_role() in ('admin', 'techSupport'))
  with check (public.app_role() in ('admin', 'techSupport'));

insert into public.news_links (id, title, url, source, sort_order) values
  ('bbf2766b-49fb-5d84-b7dd-b6ff6ac3f4ca', 'Flood Safety: What to do before, during, and after', 'https://www.redcross.org/get-help/how-to-prepare-for-emergencies/types-of-emergencies/flood.html', 'Safety Guide', 10),
  ('bd5faf7e-9426-599b-abee-95444292d858', 'NiMet Seasonal Climate Prediction', 'https://nimet.gov.ng/', 'NiMet', 20),
  ('f925b3cf-9525-54c5-a784-a0afeeb79942', 'Emergency Contact Directory: Nigeria', 'https://www.redcrossnigeria.org/', 'Red Cross', 30),
  ('4c7598b5-dc7f-561b-9afe-6f12cc62fb6c', 'Understanding Early Warning Systems', 'https://www.undrr.org/terminology/early-warning-system', 'UNDRR', 40)
on conflict (id) do nothing;

insert into public.app_settings (key, value) values
  ('support_email', '"support@cradi.org"')
on conflict (key) do nothing;


-- ============================================================================
-- SOURCE: supabase/migrations/20260927050000_alert_target_state.sql
-- ============================================================================

-- LGA names repeat across states (Obi is in Benue and in Nasarawa), so an
-- alert's target_lga alone cannot say which Obi is meant. Alerts now also
-- record the state they target:
--
--   target_state NULL  legacy / any state: target_lga matched by name only
--                      ('All' = everyone)
--   target_state S     target_lga in S only; target_lga 'All' = every LGA of S
--
-- SUPERSEDED by 20260927080000: the nullable-for-an-LGA case above lasted only
-- until that migration, which requires a state whenever target_lga names an
-- LGA (check alerts_target_lga_needs_state) and validates the pair against
-- public.nigeria_states / public.nigeria_lgas. target_state is still nullable,
-- but now only together with target_lga = 'All' (everyone, everywhere).
--
-- The backend's alert_created handler reads the column from the row (the
-- outbox payload stays { alert_id }), and pushes with the OneSignal filters
-- tag lga = ... AND tag state = .... The existing insert policy
-- (alerts_insert: staff roles, created_by = auth.uid()), the author guard and
-- the alerts_after_insert outbox trigger apply unchanged.

alter table public.alerts add column target_state text;

-- Same spelling rules as the other location columns: no blank or padded
-- values (a blank state would silently target nobody).
alter table public.alerts add constraint alerts_target_state_check
  check (target_state is null or (target_state = btrim(target_state) and target_state <> ''));

-- (20260927080000 replaces this comment once the state is mandatory.)
comment on column public.alerts.target_state is
  'State the alert targets (with target_lga, or every LGA of the state when target_lga = ''All''). NULL = legacy: target_lga matched in any state.';


-- ============================================================================
-- SOURCE: supabase/migrations/20260927060000_integrity_hardening.sql
-- ============================================================================

-- Integrity hardening from the audit:
--  1. Report content (details, location, images) can only change while the
--     report is pending and before any peer has voted on it; after that only
--     an admin can edit it. Staff can still approve / reject.
--  2. Chat rate limit can't be dodged with a client-supplied created_at /
--     sent_at: client inserts get server timestamps, updates keep the old ones.
--  3. Report rate limit is serialised per user (advisory lock) so parallel
--     inserts can't all pass the count.
--  4. EWMs only read votes on reports they can see; EWMs with an empty
--     ward / LGA match nothing.
--  5. A dispute can never verify a report: the threshold only runs for a
--     confirmation and is at least 1.
--  6. sms_deliveries: persisted authority-SMS dedupe / daily caps for the
--     Railway backend (service role only).

-- ── 1. reports: update guard (final definition) ─────────────────────────────
create or replace function public.guard_report_update()
returns trigger language plpgsql as $$
declare
  r text;
  workflow_changed boolean;
  content_changed boolean;
  location_changed boolean;
begin
  if auth.uid() is not null and pg_trigger_depth() = 1
     and not public.guard_report_update_trusted() then
    r := public.app_role();
    new.updated_by := auth.uid();

    if new.status = 'pending' and old.status is distinct from 'pending' then
      raise exception 'Use reopen_report() to move a report back to pending'
        using errcode = '42501';
    end if;

    workflow_changed :=
         new.status is distinct from old.status
      or new.approved_at is distinct from old.approved_at
      or new.rejected_at is distinct from old.rejected_at
      or new.rejection_reason is distinct from old.rejection_reason;

    location_changed :=
         new.ward is distinct from old.ward
      or new.lga is distinct from old.lga
      or new.state is distinct from old.state
      or new.latitude is distinct from old.latitude
      or new.longitude is distinct from old.longitude;

    content_changed := location_changed
      or new.hazard_type is distinct from old.hazard_type
      or new.severity is distinct from old.severity
      or new.description is distinct from old.description
      or new.location_details is distinct from old.location_details
      or new.location is distinct from old.location
      or new.address is distinct from old.address
      or new.image_urls is distinct from old.image_urls
      or new.submitted_at is distinct from old.submitted_at
      or new.type is distinct from old.type
      or new.reporter_name is distinct from old.reporter_name
      or new.created_at is distinct from old.created_at
      or new.legacy_firebase_id is distinct from old.legacy_firebase_id
      or new.synced_at is distinct from old.synced_at;

    if content_changed and r <> 'admin' then
      if old.user_id is distinct from auth.uid() then
        raise exception 'Only the reporter can edit a report''s details' using errcode = '42501';
      end if;
      -- Staff reporters pass the reports_update policy on any status, so the
      -- pending check lives here: what was reviewed / approved stays as is.
      if old.status is distinct from 'pending' then
        raise exception 'A report can only be edited while it is pending'
          using errcode = '42501';
      end if;
      -- Peers voted on what they saw; the report can't change under them.
      if public.report_has_votes(old.id) then
        raise exception 'A report cannot be edited after peers have voted on it'
          using errcode = '42501';
      end if;
    end if;

    if new.user_id is distinct from old.user_id
       or new.escalated is distinct from old.escalated
       or new.escalation_status is distinct from old.escalation_status
       or new.escalated_at is distinct from old.escalated_at
       or new.escalation_reason is distinct from old.escalation_reason
       or new.escalation_scheduled_at is distinct from old.escalation_scheduled_at then
      if r <> 'admin' then
        raise exception 'Only an admin can change report ownership or escalation'
          using errcode = '42501';
      end if;
    end if;

    -- Peer verification is counted by the verifications trigger, never by hand.
    if new.verification_count is distinct from old.verification_count
       or new.verified_at is distinct from old.verified_at
       or new.auto_validated is distinct from old.auto_validated
       or (new.status = 'verified' and old.status <> 'verified') then
      if r <> 'admin' then
        raise exception 'Reports are verified by peer confirmations' using errcode = '42501';
      end if;
    end if;

    if workflow_changed then
      if r not in ('ewv', 'ewr', 'ldp_coordinator', 'project_staff', 'admin') then
        raise exception 'Your role cannot approve, reject or reopen reports' using errcode = '42501';
      end if;
      if r <> 'admin' and old.user_id = auth.uid() then
        raise exception 'You cannot approve or reject your own report' using errcode = '42501';
      end if;
    end if;
  end if;

  -- Keep decision columns consistent with the status, whoever wrote it.
  if new.status is distinct from old.status then
    case new.status
      when 'approved' then
        new.approved_at := coalesce(new.approved_at, now());
        new.rejected_at := null;
        new.rejection_reason := null;
      when 'rejected' then
        new.rejected_at := coalesce(new.rejected_at, now());
        new.approved_at := null;
      when 'verified' then
        new.verified_at := coalesce(new.verified_at, now());
        new.approved_at := null;
        new.rejected_at := null;
        new.rejection_reason := null;
      else
        null;
    end case;
  end if;

  new.is_alert := new.severity in ('high', 'critical');
  return new;
end $$;

-- ── 2. chat: server timestamps for client writes ────────────────────────────
create or replace function public.messages_before_write()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    if auth.uid() is not null then
      -- The rate limit counts created_at, so a client can't pick it.
      new.created_at := now();
      new.sent_at := now();
      if (select count(*) from messages
           where sender_id = auth.uid() and created_at > now() - interval '1 minute') >= 30 then
        raise exception 'You are sending messages too quickly' using errcode = '54000';
      end if;
    end if;
    select coalesce(nullif(name, ''), 'User') into new.sender_name
      from profiles where id = new.sender_id;
    new.message := left(new.message, 2000);
  else
    new.sender_name := old.sender_name;
    new.sender_id := old.sender_id;
    if auth.uid() is not null then
      new.created_at := old.created_at;
      new.sent_at := old.sent_at;
    end if;
    new.message := left(new.message, 2000);
  end if;
  return new;
end $$;

-- ── 3. reports: serialised insert rate limit (final definition) ─────────────
create or replace function public.reports_before_insert()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null then
    -- Client inserts: workflow / attribution columns are server-controlled.
    -- A retry of an already-stored report (offline sync upsert) is not a new
    -- submission, so it doesn't count toward the hourly limit. The per-user
    -- lock makes concurrent inserts count each other's rows.
    perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
    if not exists (select 1 from reports where id = new.id)
       and (select count(*) from reports
             where user_id = auth.uid() and created_at > now() - interval '1 hour') >= 20 then
      raise exception 'Too many reports submitted in the last hour. Please try again later.'
        using errcode = '54000';
    end if;
    new.reporter_name := null;
    new.verification_count := 0;
    new.verified_at := null;
    new.auto_validated := false;
    new.approved_at := null;
    new.rejected_at := null;
    new.rejection_reason := null;
    new.escalated := false;
    new.escalated_at := null;
    new.escalation_reason := null;
    new.legacy_firebase_id := null;
    new.updated_by := null;
    new.created_at := now();
  end if;
  if new.reporter_name is null and new.user_id is not null then
    select name into new.reporter_name from profiles where id = new.user_id;
  end if;
  new.is_alert := new.severity in ('high', 'critical');
  if new.status = 'pending' then
    new.escalation_scheduled_at :=
      now() + make_interval(mins => public.setting_int('escalation_timeout_minutes', 30));
    new.escalation_status := 'pending';
  end if;
  return new;
end $$;

-- ── 4. EWM scoping: non-empty area; votes only on visible reports ───────────
drop policy reports_select on public.reports;
create policy reports_select on public.reports for select to authenticated
  using (
    user_id = auth.uid()
    or (public.app_role() = 'ewm'
        and coalesce(public.my_ward(), '') <> '' and coalesce(public.my_lga(), '') <> ''
        and ward = public.my_ward() and lga = public.my_lga())
    or public.app_role() in ('ewv', 'ewr', 'ldp_coordinator', 'project_staff', 'admin', 'techSupport')
  );

drop policy verifications_insert on public.verifications;
create policy verifications_insert on public.verifications for insert to authenticated
  with check (
    verifier_id = auth.uid()
    and public.is_verifier()
    and public.report_status(report_id) = 'pending'
    and public.report_owner(report_id) is distinct from auth.uid()
    and (public.app_role() <> 'ewm'
         or (coalesce(public.my_ward(), '') <> '' and coalesce(public.my_lga(), '') <> ''
             and public.report_ward(report_id) = public.my_ward()
             and public.report_lga(report_id) = public.my_lga()))
  );

-- The reports subquery runs under the caller's RLS: an EWM sees votes only
-- on reports in their own ward / LGA (or their own reports).
drop policy verifications_select on public.verifications;
create policy verifications_select on public.verifications for select to authenticated
  using (
    verifier_id = auth.uid()
    or public.app_role() in ('ewv', 'ewr', 'ldp_coordinator', 'project_staff', 'admin', 'techSupport')
    or (public.app_role() = 'ewm'
        and exists (select 1 from public.reports r where r.id = verifications.report_id))
  );

drop policy profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated
  using (
    id = auth.uid()
    or public.app_role() in ('admin', 'ldp_coordinator', 'project_staff', 'ewv', 'ewr')
    or (public.app_role() = 'ewm'
        and coalesce(public.my_ward(), '') <> '' and coalesce(public.my_lga(), '') <> ''
        and ward = public.my_ward() and lga = public.my_lga())
  );

-- ── 5. votes: only confirmations can cross the (>= 1) threshold ─────────────
create or replace function public.verifications_after_insert()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  confirmed int;
begin
  -- Serialise concurrent confirmations for the same report so each count sees
  -- the others' committed rows.
  perform 1 from reports where id = new.report_id for update;

  select count(*) into confirmed
    from verifications where report_id = new.report_id and is_confirmed;

  update reports set verification_count = confirmed where id = new.report_id;

  if new.is_confirmed
     and confirmed >= greatest(1, public.setting_int('minimum_peer_confirmations', 2)) then
    update reports
       set status = 'verified', verified_at = now(), auto_validated = true
     where id = new.report_id and status = 'pending';
  end if;
  return new;
end $$;

create or replace function public.verifications_after_update()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  confirmed int;
begin
  perform 1 from reports where id = new.report_id for update;
  select count(*) into confirmed
    from verifications where report_id = new.report_id and is_confirmed;
  update reports set verification_count = confirmed where id = new.report_id;
  if new.is_confirmed
     and confirmed >= greatest(1, public.setting_int('minimum_peer_confirmations', 2)) then
    update reports
       set status = 'verified', verified_at = now(), auto_validated = true
     where id = new.report_id and status = 'pending';
  end if;
  return new;
end $$;

-- ── 6. authority SMS deliveries (backend only) ──────────────────────────────
-- One row per (report, phone): the backend inserts a 'claimed' row before
-- texting (a conflict means already sent or in flight), marks it 'sent' or
-- 'rejected' (number refused by the provider), and deletes it after a
-- retryable failure so the outbox retry sends again. Daily per-LGA and
-- per-report caps are counted from these rows, so restarts don't reset them.
-- lga / state hold the report's values trimmed and lower-cased.
create table public.sms_deliveries (
  id          bigint generated always as identity primary key,
  report_id   uuid not null references public.reports (id) on delete cascade,
  phone       text not null,
  lga         text not null default '',
  state       text not null default '',
  status      text not null default 'claimed' check (status in ('claimed', 'sent', 'rejected')),
  created_at  timestamptz not null default now(),
  unique (report_id, phone)
);

create index sms_deliveries_cap_idx on public.sms_deliveries (lga, state, created_at);

alter table public.sms_deliveries enable row level security;
-- No client policies: only the service role (bypasses RLS) reads or writes.
revoke all on public.sms_deliveries from anon, authenticated;


-- ============================================================================
-- SOURCE: supabase/migrations/20260927070000_backfill_alert_target_state.sql
-- ============================================================================

-- Backfill alerts.target_state from target_lga.
--
-- 20260927050000 added alerts.target_state, but alerts created before it have
-- the column null, which the app and the push handler read as "legacy: match
-- target_lga by name in any state". Most LGA names occur in exactly one state,
-- so for those the state is recoverable and the alert can be pinned to it.
--
-- The mapping below is the LGA -> state table of
-- lib/core/data/nigeria_locations_data.dart (all 36 states + FCT; the three
-- covered states Benue, Nasarawa and Plateau agree with
-- lib/core/data/mvp_locations_data.dart). Only names that occur in exactly one
-- state are listed, matched case-insensitively against a trimmed target_lga.
--
-- Left alone here (the same name is an LGA of two states, so target_lga cannot
-- say which one is meant): Bassa, Ifelodun, Irepodun, Nasarawa, Obi, Surulere.
-- This migration leaves those alerts with target_state null; the very next
-- migration, 20260927080000, finishes the job — it makes the state mandatory
-- and moves any alert whose target still cannot be resolved to one place into
-- public.alerts_unresolved_target, naming each one in a WARNING, so nothing is
-- left silently matching an LGA name in every state and no admin has to hunt
-- for them.
--
-- 'All' is not an LGA name and is not in the table, so alerts targeting
-- everyone stay untouched (null state + 'All' = every state, as before).
--
-- Safety: alerts only queue a notification_outbox row from the AFTER INSERT
-- trigger alerts_after_insert, so this UPDATE sends no push. The two BEFORE
-- UPDATE triggers are alerts_touch (bumps updated_at) and alerts_guard_author
-- (rejects a change of created_by, which this does not touch).

with lga_state (lga, state) as (
  values
    ('aba north', 'Abia'),
    ('aba south', 'Abia'),
    ('abadam', 'Borno'),
    ('abaji', 'FCT'),
    ('abak', 'Akwa Ibom'),
    ('abakaliki', 'Ebonyi'),
    ('abeokuta north', 'Ogun'),
    ('abeokuta south', 'Ogun'),
    ('abi', 'Cross River'),
    ('aboh mbaise', 'Imo'),
    ('abua/odual', 'Rivers'),
    ('adavi', 'Kogi'),
    ('ado', 'Benue'),
    ('ado ekiti', 'Ekiti'),
    ('ado-odo/ota', 'Ogun'),
    ('afijio', 'Oyo'),
    ('afikpo north', 'Ebonyi'),
    ('afikpo south', 'Ebonyi'),
    ('agaie', 'Niger'),
    ('agatu', 'Benue'),
    ('agege', 'Lagos'),
    ('aguata', 'Anambra'),
    ('agwara', 'Niger'),
    ('ahiazu mbaise', 'Imo'),
    ('ahoada east', 'Rivers'),
    ('ahoada west', 'Rivers'),
    ('aiyedaade', 'Osun'),
    ('aiyedire', 'Osun'),
    ('ajaokuta', 'Kogi'),
    ('ajeromi-ifelodun', 'Lagos'),
    ('ajingi', 'Kano'),
    ('akamkpa', 'Cross River'),
    ('akinyele', 'Oyo'),
    ('akko', 'Gombe'),
    ('akoko north-east', 'Ondo'),
    ('akoko north-west', 'Ondo'),
    ('akoko south-east', 'Ondo'),
    ('akoko south-west', 'Ondo'),
    ('akoko-edo', 'Edo'),
    ('akpabuyo', 'Cross River'),
    ('akuku-toru', 'Rivers'),
    ('akure north', 'Ondo'),
    ('akure south', 'Ondo'),
    ('akwanga', 'Nasarawa'),
    ('albasu', 'Kano'),
    ('aleiro', 'Kebbi'),
    ('alimosho', 'Lagos'),
    ('alkaleri', 'Bauchi'),
    ('amuwo-odofin', 'Lagos'),
    ('anambra east', 'Anambra'),
    ('anambra west', 'Anambra'),
    ('anaocha', 'Anambra'),
    ('andoni', 'Rivers'),
    ('aninri', 'Enugu'),
    ('aniocha north', 'Delta'),
    ('aniocha south', 'Delta'),
    ('anka', 'Zamfara'),
    ('ankpa', 'Kogi'),
    ('apa', 'Benue'),
    ('apapa', 'Lagos'),
    ('ardo kola', 'Taraba'),
    ('arewa dandi', 'Kebbi'),
    ('argungu', 'Kebbi'),
    ('arochukwu', 'Abia'),
    ('asa', 'Kwara'),
    ('asari-toru', 'Rivers'),
    ('askira/uba', 'Borno'),
    ('atakunmosa east', 'Osun'),
    ('atakunmosa west', 'Osun'),
    ('atiba', 'Oyo'),
    ('atisbo', 'Oyo'),
    ('augie', 'Kebbi'),
    ('auyo', 'Jigawa'),
    ('awe', 'Nasarawa'),
    ('awgu', 'Enugu'),
    ('awka north', 'Anambra'),
    ('awka south', 'Anambra'),
    ('ayamelum', 'Anambra'),
    ('babura', 'Jigawa'),
    ('badagry', 'Lagos'),
    ('bade', 'Yobe'),
    ('bagudo', 'Kebbi'),
    ('bagwai', 'Kano'),
    ('bakassi', 'Cross River'),
    ('bakori', 'Katsina'),
    ('bakura', 'Zamfara'),
    ('balanga', 'Gombe'),
    ('bali', 'Taraba'),
    ('bama', 'Borno'),
    ('barkin ladi', 'Plateau'),
    ('baruten', 'Kwara'),
    ('batagarawa', 'Katsina'),
    ('batsari', 'Katsina'),
    ('bauchi', 'Bauchi'),
    ('baure', 'Katsina'),
    ('bayo', 'Borno'),
    ('bebeji', 'Kano'),
    ('bekwarra', 'Cross River'),
    ('bende', 'Abia'),
    ('biase', 'Cross River'),
    ('bichi', 'Kano'),
    ('bida', 'Niger'),
    ('billiri', 'Gombe'),
    ('bindawa', 'Katsina'),
    ('binji', 'Sokoto'),
    ('biriniwa', 'Jigawa'),
    ('birnin gwari', 'Kaduna'),
    ('birnin kebbi', 'Kebbi'),
    ('birnin kudu', 'Jigawa'),
    ('birnin magaji/kiyaw', 'Zamfara'),
    ('biu', 'Borno'),
    ('bodinga', 'Sokoto'),
    ('bogoro', 'Bauchi'),
    ('boki', 'Cross River'),
    ('bokkos', 'Plateau'),
    ('boluwaduro', 'Osun'),
    ('bomadi', 'Delta'),
    ('bonny', 'Rivers'),
    ('borgu', 'Niger'),
    ('boripe', 'Osun'),
    ('bosso', 'Niger'),
    ('brass', 'Bayelsa'),
    ('buji', 'Jigawa'),
    ('bukkuyum', 'Zamfara'),
    ('bungudu', 'Zamfara'),
    ('bunkure', 'Kano'),
    ('bunza', 'Kebbi'),
    ('bursari', 'Yobe'),
    ('buruku', 'Benue'),
    ('burutu', 'Delta'),
    ('bwari', 'FCT'),
    ('calabar municipal', 'Cross River'),
    ('calabar south', 'Cross River'),
    ('chafe', 'Zamfara'),
    ('chanchaga', 'Niger'),
    ('charanchi', 'Katsina'),
    ('chibok', 'Borno'),
    ('chikun', 'Kaduna'),
    ('dala', 'Kano'),
    ('damaturu', 'Yobe'),
    ('damban', 'Bauchi'),
    ('dambatta', 'Kano'),
    ('damboa', 'Borno'),
    ('dan musa', 'Katsina'),
    ('dandi', 'Kebbi'),
    ('dandume', 'Katsina'),
    ('dange shuni', 'Sokoto'),
    ('danja', 'Katsina'),
    ('darazo', 'Bauchi'),
    ('dass', 'Bauchi'),
    ('daura', 'Katsina'),
    ('dawakin kudu', 'Kano'),
    ('dawakin tofa', 'Kano'),
    ('degema', 'Rivers'),
    ('dekina', 'Kogi'),
    ('demsa', 'Adamawa'),
    ('dikwa', 'Borno'),
    ('doguwa', 'Kano'),
    ('doma', 'Nasarawa'),
    ('donga', 'Taraba'),
    ('dukku', 'Gombe'),
    ('dunukofia', 'Anambra'),
    ('dutse', 'Jigawa'),
    ('dutsi', 'Katsina'),
    ('dutsin ma', 'Katsina'),
    ('eastern obolo', 'Akwa Ibom'),
    ('ebonyi', 'Ebonyi'),
    ('edati', 'Niger'),
    ('ede north', 'Osun'),
    ('ede south', 'Osun'),
    ('edu', 'Kwara'),
    ('efe', 'Osun'),
    ('efon', 'Ekiti'),
    ('egbado north', 'Ogun'),
    ('egbado south', 'Ogun'),
    ('egbeda', 'Oyo'),
    ('egor', 'Edo'),
    ('ehime mbano', 'Imo'),
    ('ejigbo', 'Osun'),
    ('ekeremor', 'Bayelsa'),
    ('eket', 'Akwa Ibom'),
    ('ekiti', 'Kwara'),
    ('ekiti east', 'Ekiti'),
    ('ekiti south-west', 'Ekiti'),
    ('ekiti west', 'Ekiti'),
    ('ekwusigo', 'Anambra'),
    ('eleme', 'Rivers'),
    ('emohua', 'Rivers'),
    ('emure', 'Ekiti'),
    ('enugu east', 'Enugu'),
    ('enugu north', 'Enugu'),
    ('enugu south', 'Enugu'),
    ('epe', 'Lagos'),
    ('esan central', 'Edo'),
    ('esan north-east', 'Edo'),
    ('esan south-east', 'Edo'),
    ('esan west', 'Edo'),
    ('ese odo', 'Ondo'),
    ('esit eket', 'Akwa Ibom'),
    ('essien udim', 'Akwa Ibom'),
    ('etche', 'Rivers'),
    ('ethiope east', 'Delta'),
    ('ethiope west', 'Delta'),
    ('eti osa', 'Lagos'),
    ('etim ekpo', 'Akwa Ibom'),
    ('etinan', 'Akwa Ibom'),
    ('etsako central', 'Edo'),
    ('etsako east', 'Edo'),
    ('etsako west', 'Edo'),
    ('etung', 'Cross River'),
    ('ewekoro', 'Ogun'),
    ('ezeagu', 'Enugu'),
    ('ezinihitte', 'Imo'),
    ('ezza north', 'Ebonyi'),
    ('ezza south', 'Ebonyi'),
    ('fagge', 'Kano'),
    ('fakai', 'Kebbi'),
    ('faskari', 'Katsina'),
    ('fika', 'Yobe'),
    ('fufure', 'Adamawa'),
    ('funakaye', 'Gombe'),
    ('fune', 'Yobe'),
    ('funtua', 'Katsina'),
    ('gabasawa', 'Kano'),
    ('gada', 'Sokoto'),
    ('gagarawa', 'Jigawa'),
    ('gamawa', 'Bauchi'),
    ('ganjuwa', 'Bauchi'),
    ('ganye', 'Adamawa'),
    ('garki', 'Jigawa'),
    ('garko', 'Kano'),
    ('garun mallam', 'Kano'),
    ('gashaka', 'Taraba'),
    ('gassol', 'Taraba'),
    ('gaya', 'Kano'),
    ('gayuk', 'Adamawa'),
    ('gbako', 'Niger'),
    ('gboko', 'Benue'),
    ('gbonyin', 'Ekiti'),
    ('geidam', 'Yobe'),
    ('gezawa', 'Kano'),
    ('giade', 'Bauchi'),
    ('giwa', 'Kaduna'),
    ('gokana', 'Rivers'),
    ('gombe', 'Gombe'),
    ('gombi', 'Adamawa'),
    ('goronyo', 'Sokoto'),
    ('grie', 'Adamawa'),
    ('gubio', 'Borno'),
    ('gudu', 'Sokoto'),
    ('gujba', 'Yobe'),
    ('gulani', 'Yobe'),
    ('guma', 'Benue'),
    ('gumel', 'Jigawa'),
    ('gummi', 'Zamfara'),
    ('gurara', 'Niger'),
    ('guri', 'Jigawa'),
    ('gusau', 'Zamfara'),
    ('guzamala', 'Borno'),
    ('gwadabawa', 'Sokoto'),
    ('gwagwalada', 'FCT'),
    ('gwale', 'Kano'),
    ('gwandu', 'Kebbi'),
    ('gwaram', 'Jigawa'),
    ('gwarzo', 'Kano'),
    ('gwer east', 'Benue'),
    ('gwer west', 'Benue'),
    ('gwiwa', 'Jigawa'),
    ('gwoza', 'Borno'),
    ('hadejia', 'Jigawa'),
    ('hawul', 'Borno'),
    ('hong', 'Adamawa'),
    ('ibadan north', 'Oyo'),
    ('ibadan north-east', 'Oyo'),
    ('ibadan north-west', 'Oyo'),
    ('ibadan south-east', 'Oyo'),
    ('ibadan south-west', 'Oyo'),
    ('ibaji', 'Kogi'),
    ('ibarapa central', 'Oyo'),
    ('ibarapa east', 'Oyo'),
    ('ibarapa north', 'Oyo'),
    ('ibeju-lekki', 'Lagos'),
    ('ibeno', 'Akwa Ibom'),
    ('ibesikpo asutan', 'Akwa Ibom'),
    ('ibi', 'Taraba'),
    ('ibiono-ibom', 'Akwa Ibom'),
    ('idah', 'Kogi'),
    ('idanre', 'Ondo'),
    ('ideato north', 'Imo'),
    ('ideato south', 'Imo'),
    ('idemili north', 'Anambra'),
    ('idemili south', 'Anambra'),
    ('ido', 'Oyo'),
    ('ido osi', 'Ekiti'),
    ('ifako-ijaiye', 'Lagos'),
    ('ifedayo', 'Osun'),
    ('ifedore', 'Ondo'),
    ('ifo', 'Ogun'),
    ('igabi', 'Kaduna'),
    ('igalamela odolu', 'Kogi'),
    ('igbo etiti', 'Enugu'),
    ('igbo eze north', 'Enugu'),
    ('igbo eze south', 'Enugu'),
    ('igueben', 'Edo'),
    ('ihiala', 'Anambra'),
    ('ihitte/uboma', 'Imo'),
    ('ijebu east', 'Ogun'),
    ('ijebu north', 'Ogun'),
    ('ijebu north east', 'Ogun'),
    ('ijebu ode', 'Ogun'),
    ('ijero', 'Ekiti'),
    ('ijumu', 'Kogi'),
    ('ika', 'Akwa Ibom'),
    ('ika north east', 'Delta'),
    ('ika south', 'Delta'),
    ('ikara', 'Kaduna'),
    ('ikeduru', 'Imo'),
    ('ikeja', 'Lagos'),
    ('ikenne', 'Ogun'),
    ('ikere', 'Ekiti'),
    ('ikole', 'Ekiti'),
    ('ikom', 'Cross River'),
    ('ikono', 'Akwa Ibom'),
    ('ikorodu', 'Lagos'),
    ('ikot abasi', 'Akwa Ibom'),
    ('ikot ekpene', 'Akwa Ibom'),
    ('ikpoba okha', 'Edo'),
    ('ikwerre', 'Rivers'),
    ('ikwo', 'Ebonyi'),
    ('ikwuano', 'Abia'),
    ('ila', 'Osun'),
    ('ilaje', 'Ondo'),
    ('ile oluji/okeigbo', 'Ondo'),
    ('ilejemeje', 'Ekiti'),
    ('ilesa east', 'Osun'),
    ('ilesa west', 'Osun'),
    ('illela', 'Sokoto'),
    ('ilorin east', 'Kwara'),
    ('ilorin south', 'Kwara'),
    ('ilorin west', 'Kwara'),
    ('imeko afon', 'Ogun'),
    ('ingawa', 'Katsina'),
    ('ini', 'Akwa Ibom'),
    ('ipokia', 'Ogun'),
    ('irele', 'Ondo'),
    ('irepo', 'Oyo'),
    ('irepodun/ifelodun', 'Ekiti'),
    ('irewole', 'Osun'),
    ('isa', 'Sokoto'),
    ('ise/orun', 'Ekiti'),
    ('iseyin', 'Oyo'),
    ('ishielu', 'Ebonyi'),
    ('isi uzo', 'Enugu'),
    ('isiala mbano', 'Imo'),
    ('isiala ngwa north', 'Abia'),
    ('isiala ngwa south', 'Abia'),
    ('isin', 'Kwara'),
    ('isokan', 'Osun'),
    ('isoko north', 'Delta'),
    ('isoko south', 'Delta'),
    ('isu', 'Imo'),
    ('isuikwuato', 'Abia'),
    ('itas/gadau', 'Bauchi'),
    ('itesiwaju', 'Oyo'),
    ('itu', 'Akwa Ibom'),
    ('ivo', 'Ebonyi'),
    ('iwajowa', 'Oyo'),
    ('iwo', 'Osun'),
    ('izzi', 'Ebonyi'),
    ('jaba', 'Kaduna'),
    ('jada', 'Adamawa'),
    ('jahun', 'Jigawa'),
    ('jakusko', 'Yobe'),
    ('jalingo', 'Taraba'),
    ('jama''are', 'Bauchi'),
    ('jega', 'Kebbi'),
    ('jema''a', 'Kaduna'),
    ('jere', 'Borno'),
    ('jibia', 'Katsina'),
    ('jos east', 'Plateau'),
    ('jos north', 'Plateau'),
    ('jos south', 'Plateau'),
    ('kabba/bunu', 'Kogi'),
    ('kabo', 'Kano'),
    ('kachia', 'Kaduna'),
    ('kaduna north', 'Kaduna'),
    ('kaduna south', 'Kaduna'),
    ('kafin hausa', 'Jigawa'),
    ('kafur', 'Katsina'),
    ('kaga', 'Borno'),
    ('kagarko', 'Kaduna'),
    ('kaiama', 'Kwara'),
    ('kaita', 'Katsina'),
    ('kajola', 'Oyo'),
    ('kajuru', 'Kaduna'),
    ('kala/balge', 'Borno'),
    ('kalgo', 'Kebbi'),
    ('kaltungo', 'Gombe'),
    ('kanam', 'Plateau'),
    ('kankara', 'Katsina'),
    ('kanke', 'Plateau'),
    ('kankia', 'Katsina'),
    ('kano municipal', 'Kano'),
    ('karasuwa', 'Yobe'),
    ('karaye', 'Kano'),
    ('karim lamido', 'Taraba'),
    ('karu', 'Nasarawa'),
    ('katagum', 'Bauchi'),
    ('katcha', 'Niger'),
    ('katsina', 'Katsina'),
    ('katsina-ala', 'Benue'),
    ('kaugama', 'Jigawa'),
    ('kaura', 'Kaduna'),
    ('kaura namoda', 'Zamfara'),
    ('kauru', 'Kaduna'),
    ('kazaure', 'Jigawa'),
    ('keana', 'Nasarawa'),
    ('kebbe', 'Sokoto'),
    ('keffi', 'Nasarawa'),
    ('khana', 'Rivers'),
    ('kibiya', 'Kano'),
    ('kirfi', 'Bauchi'),
    ('kiri kasama', 'Jigawa'),
    ('kiru', 'Kano'),
    ('kiyawa', 'Jigawa'),
    ('kogi', 'Kogi'),
    ('koko/besse', 'Kebbi'),
    ('kokona', 'Nasarawa'),
    ('kolokuma/opokuma', 'Bayelsa'),
    ('konduga', 'Borno'),
    ('konshisha', 'Benue'),
    ('kontagora', 'Niger'),
    ('kosofe', 'Lagos'),
    ('kubau', 'Kaduna'),
    ('kudan', 'Kaduna'),
    ('kuje', 'FCT'),
    ('kukawa', 'Borno'),
    ('kumbotso', 'Kano'),
    ('kumi', 'Taraba'),
    ('kunchi', 'Kano'),
    ('kura', 'Kano'),
    ('kurfi', 'Katsina'),
    ('kusada', 'Katsina'),
    ('kwali', 'FCT'),
    ('kwami', 'Gombe'),
    ('kwande', 'Benue'),
    ('kware', 'Sokoto'),
    ('kwaya kusar', 'Borno'),
    ('lafia', 'Nasarawa'),
    ('lagelu', 'Oyo'),
    ('lagos island', 'Lagos'),
    ('lagos mainland', 'Lagos'),
    ('lamurde', 'Adamawa'),
    ('langtang north', 'Plateau'),
    ('langtang south', 'Plateau'),
    ('lapai', 'Niger'),
    ('lau', 'Taraba'),
    ('lavun', 'Niger'),
    ('lere', 'Kaduna'),
    ('logo', 'Benue'),
    ('lokoja', 'Kogi'),
    ('machina', 'Yobe'),
    ('madagali', 'Adamawa'),
    ('madobi', 'Kano'),
    ('mafa', 'Borno'),
    ('magama', 'Niger'),
    ('magumeri', 'Borno'),
    ('mai''adua', 'Katsina'),
    ('maiduguri', 'Borno'),
    ('maigatari', 'Jigawa'),
    ('maiha', 'Adamawa'),
    ('maiyama', 'Kebbi'),
    ('makarfi', 'Kaduna'),
    ('makoda', 'Kano'),
    ('makurdi', 'Benue'),
    ('malam madori', 'Jigawa'),
    ('malumfashi', 'Katsina'),
    ('mangu', 'Plateau'),
    ('mani', 'Katsina'),
    ('maradun', 'Zamfara'),
    ('mariga', 'Niger'),
    ('marte', 'Borno'),
    ('maru', 'Zamfara'),
    ('mashegu', 'Niger'),
    ('mashi', 'Katsina'),
    ('matazu', 'Katsina'),
    ('mayo belwa', 'Adamawa'),
    ('mbaitoli', 'Imo'),
    ('mbo', 'Akwa Ibom'),
    ('michika', 'Adamawa'),
    ('miga', 'Jigawa'),
    ('mikang', 'Plateau'),
    ('minjibir', 'Kano'),
    ('misau', 'Bauchi'),
    ('mkpat-enin', 'Akwa Ibom'),
    ('moba', 'Ekiti'),
    ('mobbar', 'Borno'),
    ('mokwa', 'Niger'),
    ('monguno', 'Borno'),
    ('mopa muro', 'Kogi'),
    ('moro', 'Kwara'),
    ('moya', 'Niger'),
    ('mubi north', 'Adamawa'),
    ('mubi south', 'Adamawa'),
    ('municipal area council', 'FCT'),
    ('musawa', 'Katsina'),
    ('mushin', 'Lagos'),
    ('nafada', 'Gombe'),
    ('nangere', 'Yobe'),
    ('nasarawa egon', 'Nasarawa'),
    ('ndokwa east', 'Delta'),
    ('ndokwa west', 'Delta'),
    ('nembe', 'Bayelsa'),
    ('ngala', 'Borno'),
    ('nganzai', 'Borno'),
    ('ngaski', 'Kebbi'),
    ('ngor okpala', 'Imo'),
    ('nguru', 'Yobe'),
    ('ningi', 'Bauchi'),
    ('njaba', 'Imo'),
    ('njikoka', 'Anambra'),
    ('nkanu east', 'Enugu'),
    ('nkanu west', 'Enugu'),
    ('nkwerre', 'Imo'),
    ('nnewi north', 'Anambra'),
    ('nnewi south', 'Anambra'),
    ('nsit-atai', 'Akwa Ibom'),
    ('nsit-ibom', 'Akwa Ibom'),
    ('nsit-ubium', 'Akwa Ibom'),
    ('nsukka', 'Enugu'),
    ('numan', 'Adamawa'),
    ('nwangele', 'Imo'),
    ('obafemi owode', 'Ogun'),
    ('obanliku', 'Cross River'),
    ('obi ngwa', 'Abia'),
    ('obio/akpor', 'Rivers'),
    ('obokun', 'Osun'),
    ('obot akara', 'Akwa Ibom'),
    ('obowo', 'Imo'),
    ('obubra', 'Cross River'),
    ('obudu', 'Cross River'),
    ('odeda', 'Ogun'),
    ('odigbo', 'Ondo'),
    ('odo otin', 'Osun'),
    ('odogbolu', 'Ogun'),
    ('odukpani', 'Cross River'),
    ('offa', 'Kwara'),
    ('ofu', 'Kogi'),
    ('ogba/egbema/ndoni', 'Rivers'),
    ('ogbadibo', 'Benue'),
    ('ogbaru', 'Anambra'),
    ('ogbia', 'Bayelsa'),
    ('ogbomosho north', 'Oyo'),
    ('ogbomosho south', 'Oyo'),
    ('ogo oluwa', 'Oyo'),
    ('ogoja', 'Cross River'),
    ('ogori/magongo', 'Kogi'),
    ('ogu/bolo', 'Rivers'),
    ('ogun waterside', 'Ogun'),
    ('oguta', 'Imo'),
    ('ohafia', 'Abia'),
    ('ohaji/egbema', 'Imo'),
    ('ohaozara', 'Ebonyi'),
    ('ohaukwu', 'Ebonyi'),
    ('ohimini', 'Benue'),
    ('oji river', 'Enugu'),
    ('ojo', 'Lagos'),
    ('oju', 'Benue'),
    ('oke ero', 'Kwara'),
    ('okehi', 'Kogi'),
    ('okene', 'Kogi'),
    ('okigwe', 'Imo'),
    ('okitipupa', 'Ondo'),
    ('okobo', 'Akwa Ibom'),
    ('okpe', 'Delta'),
    ('okpokwu', 'Benue'),
    ('okrika', 'Rivers'),
    ('ola oluwa', 'Osun'),
    ('olamaboro', 'Kogi'),
    ('olorunda', 'Osun'),
    ('olorunsogo', 'Oyo'),
    ('oluyole', 'Oyo'),
    ('omala', 'Kogi'),
    ('omuma', 'Rivers'),
    ('ona ara', 'Oyo'),
    ('ondo east', 'Ondo'),
    ('ondo west', 'Ondo'),
    ('onicha', 'Ebonyi'),
    ('onitsha north', 'Anambra'),
    ('onitsha south', 'Anambra'),
    ('onna', 'Akwa Ibom'),
    ('opobo/nkoro', 'Rivers'),
    ('oredo', 'Edo'),
    ('orelope', 'Oyo'),
    ('orhionmwon', 'Edo'),
    ('ori ire', 'Oyo'),
    ('oriade', 'Osun'),
    ('orlu', 'Imo'),
    ('orolu', 'Osun'),
    ('oron', 'Akwa Ibom'),
    ('orsu', 'Imo'),
    ('oru east', 'Imo'),
    ('oru west', 'Imo'),
    ('oruk anam', 'Akwa Ibom'),
    ('orumba north', 'Anambra'),
    ('orumba south', 'Anambra'),
    ('ose', 'Ondo'),
    ('oshimili north', 'Delta'),
    ('oshimili south', 'Delta'),
    ('oshodi-isolo', 'Lagos'),
    ('osisioma', 'Abia'),
    ('osogbo', 'Osun'),
    ('oturkpo', 'Benue'),
    ('ovia north-east', 'Edo'),
    ('ovia south-west', 'Edo'),
    ('owan east', 'Edo'),
    ('owan west', 'Edo'),
    ('owerri municipal', 'Imo'),
    ('owerri north', 'Imo'),
    ('owerri west', 'Imo'),
    ('owo', 'Ondo'),
    ('oye', 'Ekiti'),
    ('oyi', 'Anambra'),
    ('oyigbo', 'Rivers'),
    ('oyo east', 'Oyo'),
    ('oyo west', 'Oyo'),
    ('oyun', 'Kwara'),
    ('paikoro', 'Niger'),
    ('pankshin', 'Plateau'),
    ('patani', 'Delta'),
    ('pategi', 'Kwara'),
    ('port harcourt', 'Rivers'),
    ('potiskum', 'Yobe'),
    ('qua''an pan', 'Plateau'),
    ('rabah', 'Sokoto'),
    ('rafi', 'Niger'),
    ('rano', 'Kano'),
    ('remo north', 'Ogun'),
    ('rijau', 'Niger'),
    ('rimi', 'Katsina'),
    ('rimin gado', 'Kano'),
    ('ringim', 'Jigawa'),
    ('riyom', 'Plateau'),
    ('rogo', 'Kano'),
    ('roni', 'Jigawa'),
    ('sabon birni', 'Sokoto'),
    ('sabon gari', 'Kaduna'),
    ('sabuwa', 'Katsina'),
    ('safana', 'Katsina'),
    ('sagbama', 'Bayelsa'),
    ('sakaba', 'Kebbi'),
    ('saki east', 'Oyo'),
    ('saki west', 'Oyo'),
    ('sandamu', 'Katsina'),
    ('sanga', 'Kaduna'),
    ('sapele', 'Delta'),
    ('sardauna', 'Taraba'),
    ('shagamu', 'Ogun'),
    ('shagari', 'Sokoto'),
    ('shanga', 'Kebbi'),
    ('shani', 'Borno'),
    ('shanono', 'Kano'),
    ('shelleng', 'Adamawa'),
    ('shendam', 'Plateau'),
    ('shinkafi', 'Zamfara'),
    ('shira', 'Bauchi'),
    ('shiroro', 'Niger'),
    ('shomolu', 'Lagos'),
    ('shongom', 'Gombe'),
    ('silame', 'Sokoto'),
    ('soba', 'Kaduna'),
    ('sokoto north', 'Sokoto'),
    ('sokoto south', 'Sokoto'),
    ('song', 'Adamawa'),
    ('southern ijaw', 'Bayelsa'),
    ('sule tankarkar', 'Jigawa'),
    ('suleja', 'Niger'),
    ('sumaila', 'Kano'),
    ('suru', 'Kebbi'),
    ('tafa', 'Niger'),
    ('tafawa balewa', 'Bauchi'),
    ('tai', 'Rivers'),
    ('takai', 'Kano'),
    ('takum', 'Taraba'),
    ('talata mafara', 'Zamfara'),
    ('tambuwal', 'Sokoto'),
    ('tangaza', 'Sokoto'),
    ('tarauni', 'Kano'),
    ('tarka', 'Benue'),
    ('tarmuwa', 'Yobe'),
    ('taura', 'Jigawa'),
    ('tofa', 'Kano'),
    ('toro', 'Bauchi'),
    ('toto', 'Nasarawa'),
    ('toungo', 'Adamawa'),
    ('tsanyawa', 'Kano'),
    ('tudun wada', 'Kano'),
    ('tureta', 'Sokoto'),
    ('udenu', 'Enugu'),
    ('udi', 'Enugu'),
    ('udu', 'Delta'),
    ('udung-uko', 'Akwa Ibom'),
    ('ughelli north', 'Delta'),
    ('ughelli south', 'Delta'),
    ('ugwunagbo', 'Abia'),
    ('uhunmwonde', 'Edo'),
    ('ukanafun', 'Akwa Ibom'),
    ('ukum', 'Benue'),
    ('ukwa east', 'Abia'),
    ('ukwa west', 'Abia'),
    ('ukwuani', 'Delta'),
    ('umu nneochi', 'Abia'),
    ('umuahia north', 'Abia'),
    ('umuahia south', 'Abia'),
    ('ungogo', 'Kano'),
    ('unuimo', 'Imo'),
    ('uruan', 'Akwa Ibom'),
    ('urue-offong/oruko', 'Akwa Ibom'),
    ('ushongo', 'Benue'),
    ('ussa', 'Taraba'),
    ('uvwie', 'Delta'),
    ('uyo', 'Akwa Ibom'),
    ('uzo uwani', 'Enugu'),
    ('vandeikya', 'Benue'),
    ('wamako', 'Sokoto'),
    ('wamba', 'Nasarawa'),
    ('warawa', 'Kano'),
    ('warji', 'Bauchi'),
    ('warri north', 'Delta'),
    ('warri south', 'Delta'),
    ('warri south west', 'Delta'),
    ('wasagu/danko', 'Kebbi'),
    ('wase', 'Plateau'),
    ('wudil', 'Kano'),
    ('wukari', 'Taraba'),
    ('wurno', 'Sokoto'),
    ('wushishi', 'Niger'),
    ('yabo', 'Sokoto'),
    ('yagba east', 'Kogi'),
    ('yagba west', 'Kogi'),
    ('yakuur', 'Cross River'),
    ('yala', 'Cross River'),
    ('yamaltu/deba', 'Gombe'),
    ('yankwashi', 'Jigawa'),
    ('yauri', 'Kebbi'),
    ('yenagoa', 'Bayelsa'),
    ('yola north', 'Adamawa'),
    ('yola south', 'Adamawa'),
    ('yorro', 'Taraba'),
    ('yunusari', 'Yobe'),
    ('yusufari', 'Yobe'),
    ('zaki', 'Bauchi'),
    ('zango', 'Katsina'),
    ('zangon kataf', 'Kaduna'),
    ('zaria', 'Kaduna'),
    ('zing', 'Taraba'),
    ('zurmi', 'Zamfara'),
    ('zuru', 'Kebbi')
),
unambiguous as (
  select lga, min(state) as state
  from lga_state
  group by lga
  having count(distinct state) = 1
)
update public.alerts a
   set target_state = u.state
  from unambiguous u
 where a.target_state is null
   and a.target_lga is not null
   and lower(btrim(a.target_lga)) = u.lga;


-- ============================================================================
-- SOURCE: supabase/migrations/20260927080000_alert_state_required.sql
-- ============================================================================

-- Alerts must name the state of the LGA they target.
--
-- 20260927050000 added alerts.target_state but left it nullable, so an alert
-- could still name an LGA and no state — and 6 of the 770 LGA names are not
-- unique, so that alert had no single meaning:
--
--   Bassa      Kogi, Plateau      Nasarawa   Kano, Nasarawa
--   Ifelodun   Kwara, Osun        Obi        Benue, Nasarawa
--   Irepodun   Kwara, Osun        Surulere   Lagos, Oyo
--
-- (derived from lib/core/data/nigeria_locations_data.dart, the app's canonical
-- 37 states / 770 LGAs; lib/core/data/mvp_locations_data.dart's 53 LGAs for
-- Benue, Nasarawa and Plateau are a spelling-identical subset of it.)
--
-- From here on the database rejects that shape outright. The four targetings
-- that remain expressible are exactly the four the push filter builder
-- (backend/src/notifications.js alertTarget) and the app's alert list
-- (lib/features/alerts/providers/alerts_provider.dart targetsLga) understand:
--
--   target_state NULL, target_lga 'All'  -> everyone, everywhere
--   target_state S,    target_lga 'All'  -> every LGA of S
--   target_state S,    target_lga X      -> X in S only
--   target_state NULL, target_lga X      -> REJECTED (which X?)
--
-- Why two reference tables rather than a literal list in the CHECK
--   A CHECK can only hold a constant expression, so pinning 770 (state, LGA)
--   pairs into one would mean a 770-entry IN list repeated in every future
--   migration that touched it — exactly the unmaintainable literal list to
--   avoid. 20260927070000 already carries that list once as an inline VALUES
--   list, usable only by that one UPDATE. Persisting it instead as
--   public.nigeria_states / public.nigeria_lgas lets a plain FOREIGN KEY do
--   the validation, and leaves the same canonical data available to future
--   migrations, admin queries and RPCs (it is the only copy of it in the
--   database). Both tables are seeded from nigeria_locations_data.dart and are
--   client-read-only.

-- ── Canonical Nigerian states and LGAs ──────────────────────────────────────

create table public.nigeria_states (
  name text primary key check (name = btrim(name) and name <> '')
);

create table public.nigeria_lgas (
  state text not null references public.nigeria_states (name),
  lga   text not null check (lga = btrim(lga) and lga <> ''),
  primary key (state, lga)
);

-- Lookups by LGA name alone (used by the backfill below and by anything that
-- needs "which states have an LGA called X").
create index nigeria_lgas_lga_idx on public.nigeria_lgas (lower(lga));

insert into public.nigeria_states (name) values
  ('Abia'),
  ('Adamawa'),
  ('Akwa Ibom'),
  ('Anambra'),
  ('Bauchi'),
  ('Bayelsa'),
  ('Benue'),
  ('Borno'),
  ('Cross River'),
  ('Delta'),
  ('Ebonyi'),
  ('Edo'),
  ('Ekiti'),
  ('Enugu'),
  ('FCT'),
  ('Gombe'),
  ('Imo'),
  ('Jigawa'),
  ('Kaduna'),
  ('Kano'),
  ('Katsina'),
  ('Kebbi'),
  ('Kogi'),
  ('Kwara'),
  ('Lagos'),
  ('Nasarawa'),
  ('Niger'),
  ('Ogun'),
  ('Ondo'),
  ('Osun'),
  ('Oyo'),
  ('Plateau'),
  ('Rivers'),
  ('Sokoto'),
  ('Taraba'),
  ('Yobe'),
  ('Zamfara');

insert into public.nigeria_lgas (state, lga) values
  ('Abia', 'Aba North'),
  ('Abia', 'Aba South'),
  ('Abia', 'Arochukwu'),
  ('Abia', 'Bende'),
  ('Abia', 'Ikwuano'),
  ('Abia', 'Isiala Ngwa North'),
  ('Abia', 'Isiala Ngwa South'),
  ('Abia', 'Isuikwuato'),
  ('Abia', 'Obi Ngwa'),
  ('Abia', 'Ohafia'),
  ('Abia', 'Osisioma'),
  ('Abia', 'Ugwunagbo'),
  ('Abia', 'Ukwa East'),
  ('Abia', 'Ukwa West'),
  ('Abia', 'Umuahia North'),
  ('Abia', 'Umuahia South'),
  ('Abia', 'Umu Nneochi'),
  ('Adamawa', 'Demsa'),
  ('Adamawa', 'Fufure'),
  ('Adamawa', 'Ganye'),
  ('Adamawa', 'Gayuk'),
  ('Adamawa', 'Gombi'),
  ('Adamawa', 'Grie'),
  ('Adamawa', 'Hong'),
  ('Adamawa', 'Jada'),
  ('Adamawa', 'Lamurde'),
  ('Adamawa', 'Madagali'),
  ('Adamawa', 'Maiha'),
  ('Adamawa', 'Mayo Belwa'),
  ('Adamawa', 'Michika'),
  ('Adamawa', 'Mubi North'),
  ('Adamawa', 'Mubi South'),
  ('Adamawa', 'Numan'),
  ('Adamawa', 'Shelleng'),
  ('Adamawa', 'Song'),
  ('Adamawa', 'Toungo'),
  ('Adamawa', 'Yola North'),
  ('Adamawa', 'Yola South'),
  ('Akwa Ibom', 'Abak'),
  ('Akwa Ibom', 'Eastern Obolo'),
  ('Akwa Ibom', 'Eket'),
  ('Akwa Ibom', 'Esit Eket'),
  ('Akwa Ibom', 'Essien Udim'),
  ('Akwa Ibom', 'Etim Ekpo'),
  ('Akwa Ibom', 'Etinan'),
  ('Akwa Ibom', 'Ibeno'),
  ('Akwa Ibom', 'Ibesikpo Asutan'),
  ('Akwa Ibom', 'Ibiono-Ibom'),
  ('Akwa Ibom', 'Ika'),
  ('Akwa Ibom', 'Ikono'),
  ('Akwa Ibom', 'Ikot Abasi'),
  ('Akwa Ibom', 'Ikot Ekpene'),
  ('Akwa Ibom', 'Ini'),
  ('Akwa Ibom', 'Itu'),
  ('Akwa Ibom', 'Mbo'),
  ('Akwa Ibom', 'Mkpat-Enin'),
  ('Akwa Ibom', 'Nsit-Atai'),
  ('Akwa Ibom', 'Nsit-Ibom'),
  ('Akwa Ibom', 'Nsit-Ubium'),
  ('Akwa Ibom', 'Obot Akara'),
  ('Akwa Ibom', 'Okobo'),
  ('Akwa Ibom', 'Onna'),
  ('Akwa Ibom', 'Oron'),
  ('Akwa Ibom', 'Oruk Anam'),
  ('Akwa Ibom', 'Udung-Uko'),
  ('Akwa Ibom', 'Ukanafun'),
  ('Akwa Ibom', 'Uruan'),
  ('Akwa Ibom', 'Urue-Offong/Oruko'),
  ('Akwa Ibom', 'Uyo'),
  ('Anambra', 'Aguata'),
  ('Anambra', 'Anambra East'),
  ('Anambra', 'Anambra West'),
  ('Anambra', 'Anaocha'),
  ('Anambra', 'Awka North'),
  ('Anambra', 'Awka South'),
  ('Anambra', 'Ayamelum'),
  ('Anambra', 'Dunukofia'),
  ('Anambra', 'Ekwusigo'),
  ('Anambra', 'Idemili North'),
  ('Anambra', 'Idemili South'),
  ('Anambra', 'Ihiala'),
  ('Anambra', 'Njikoka'),
  ('Anambra', 'Nnewi North'),
  ('Anambra', 'Nnewi South'),
  ('Anambra', 'Ogbaru'),
  ('Anambra', 'Onitsha North'),
  ('Anambra', 'Onitsha South'),
  ('Anambra', 'Orumba North'),
  ('Anambra', 'Orumba South'),
  ('Anambra', 'Oyi'),
  ('Bauchi', 'Alkaleri'),
  ('Bauchi', 'Bauchi'),
  ('Bauchi', 'Bogoro'),
  ('Bauchi', 'Damban'),
  ('Bauchi', 'Darazo'),
  ('Bauchi', 'Dass'),
  ('Bauchi', 'Gamawa'),
  ('Bauchi', 'Ganjuwa'),
  ('Bauchi', 'Giade'),
  ('Bauchi', 'Itas/Gadau'),
  ('Bauchi', 'Jama''are'),
  ('Bauchi', 'Katagum'),
  ('Bauchi', 'Kirfi'),
  ('Bauchi', 'Misau'),
  ('Bauchi', 'Ningi'),
  ('Bauchi', 'Shira'),
  ('Bauchi', 'Tafawa Balewa'),
  ('Bauchi', 'Toro'),
  ('Bauchi', 'Warji'),
  ('Bauchi', 'Zaki'),
  ('Bayelsa', 'Brass'),
  ('Bayelsa', 'Ekeremor'),
  ('Bayelsa', 'Kolokuma/Opokuma'),
  ('Bayelsa', 'Nembe'),
  ('Bayelsa', 'Ogbia'),
  ('Bayelsa', 'Sagbama'),
  ('Bayelsa', 'Southern Ijaw'),
  ('Bayelsa', 'Yenagoa'),
  ('Benue', 'Ado'),
  ('Benue', 'Agatu'),
  ('Benue', 'Apa'),
  ('Benue', 'Buruku'),
  ('Benue', 'Gboko'),
  ('Benue', 'Guma'),
  ('Benue', 'Gwer East'),
  ('Benue', 'Gwer West'),
  ('Benue', 'Katsina-Ala'),
  ('Benue', 'Konshisha'),
  ('Benue', 'Kwande'),
  ('Benue', 'Logo'),
  ('Benue', 'Makurdi'),
  ('Benue', 'Obi'),
  ('Benue', 'Ogbadibo'),
  ('Benue', 'Ohimini'),
  ('Benue', 'Oju'),
  ('Benue', 'Okpokwu'),
  ('Benue', 'Oturkpo'),
  ('Benue', 'Tarka'),
  ('Benue', 'Ukum'),
  ('Benue', 'Ushongo'),
  ('Benue', 'Vandeikya'),
  ('Borno', 'Abadam'),
  ('Borno', 'Askira/Uba'),
  ('Borno', 'Bama'),
  ('Borno', 'Bayo'),
  ('Borno', 'Biu'),
  ('Borno', 'Chibok'),
  ('Borno', 'Damboa'),
  ('Borno', 'Dikwa'),
  ('Borno', 'Gubio'),
  ('Borno', 'Guzamala'),
  ('Borno', 'Gwoza'),
  ('Borno', 'Hawul'),
  ('Borno', 'Jere'),
  ('Borno', 'Kaga'),
  ('Borno', 'Kala/Balge'),
  ('Borno', 'Konduga'),
  ('Borno', 'Kukawa'),
  ('Borno', 'Kwaya Kusar'),
  ('Borno', 'Mafa'),
  ('Borno', 'Magumeri'),
  ('Borno', 'Maiduguri'),
  ('Borno', 'Marte'),
  ('Borno', 'Mobbar'),
  ('Borno', 'Monguno'),
  ('Borno', 'Ngala'),
  ('Borno', 'Nganzai'),
  ('Borno', 'Shani'),
  ('Cross River', 'Abi'),
  ('Cross River', 'Akamkpa'),
  ('Cross River', 'Akpabuyo'),
  ('Cross River', 'Bakassi'),
  ('Cross River', 'Bekwarra'),
  ('Cross River', 'Biase'),
  ('Cross River', 'Boki'),
  ('Cross River', 'Calabar Municipal'),
  ('Cross River', 'Calabar South'),
  ('Cross River', 'Etung'),
  ('Cross River', 'Ikom'),
  ('Cross River', 'Obanliku'),
  ('Cross River', 'Obubra'),
  ('Cross River', 'Obudu'),
  ('Cross River', 'Odukpani'),
  ('Cross River', 'Ogoja'),
  ('Cross River', 'Yakuur'),
  ('Cross River', 'Yala'),
  ('Delta', 'Aniocha North'),
  ('Delta', 'Aniocha South'),
  ('Delta', 'Bomadi'),
  ('Delta', 'Burutu'),
  ('Delta', 'Ethiope East'),
  ('Delta', 'Ethiope West'),
  ('Delta', 'Ika North East'),
  ('Delta', 'Ika South'),
  ('Delta', 'Isoko North'),
  ('Delta', 'Isoko South'),
  ('Delta', 'Ndokwa East'),
  ('Delta', 'Ndokwa West'),
  ('Delta', 'Okpe'),
  ('Delta', 'Oshimili North'),
  ('Delta', 'Oshimili South'),
  ('Delta', 'Patani'),
  ('Delta', 'Sapele'),
  ('Delta', 'Udu'),
  ('Delta', 'Ughelli North'),
  ('Delta', 'Ughelli South'),
  ('Delta', 'Ukwuani'),
  ('Delta', 'Uvwie'),
  ('Delta', 'Warri North'),
  ('Delta', 'Warri South'),
  ('Delta', 'Warri South West'),
  ('Ebonyi', 'Abakaliki'),
  ('Ebonyi', 'Afikpo North'),
  ('Ebonyi', 'Afikpo South'),
  ('Ebonyi', 'Ebonyi'),
  ('Ebonyi', 'Ezza North'),
  ('Ebonyi', 'Ezza South'),
  ('Ebonyi', 'Ikwo'),
  ('Ebonyi', 'Ishielu'),
  ('Ebonyi', 'Ivo'),
  ('Ebonyi', 'Izzi'),
  ('Ebonyi', 'Ohaozara'),
  ('Ebonyi', 'Ohaukwu'),
  ('Ebonyi', 'Onicha'),
  ('Edo', 'Akoko-Edo'),
  ('Edo', 'Egor'),
  ('Edo', 'Esan Central'),
  ('Edo', 'Esan North-East'),
  ('Edo', 'Esan South-East'),
  ('Edo', 'Esan West'),
  ('Edo', 'Etsako Central'),
  ('Edo', 'Etsako East'),
  ('Edo', 'Etsako West'),
  ('Edo', 'Igueben'),
  ('Edo', 'Ikpoba Okha'),
  ('Edo', 'Orhionmwon'),
  ('Edo', 'Oredo'),
  ('Edo', 'Ovia North-East'),
  ('Edo', 'Ovia South-West'),
  ('Edo', 'Owan East'),
  ('Edo', 'Owan West'),
  ('Edo', 'Uhunmwonde'),
  ('Ekiti', 'Ado Ekiti'),
  ('Ekiti', 'Efon'),
  ('Ekiti', 'Ekiti East'),
  ('Ekiti', 'Ekiti South-West'),
  ('Ekiti', 'Ekiti West'),
  ('Ekiti', 'Emure'),
  ('Ekiti', 'Gbonyin'),
  ('Ekiti', 'Ido Osi'),
  ('Ekiti', 'Ijero'),
  ('Ekiti', 'Ikere'),
  ('Ekiti', 'Ikole'),
  ('Ekiti', 'Ilejemeje'),
  ('Ekiti', 'Irepodun/Ifelodun'),
  ('Ekiti', 'Ise/Orun'),
  ('Ekiti', 'Moba'),
  ('Ekiti', 'Oye'),
  ('Enugu', 'Aninri'),
  ('Enugu', 'Awgu'),
  ('Enugu', 'Enugu East'),
  ('Enugu', 'Enugu North'),
  ('Enugu', 'Enugu South'),
  ('Enugu', 'Ezeagu'),
  ('Enugu', 'Igbo Etiti'),
  ('Enugu', 'Igbo Eze North'),
  ('Enugu', 'Igbo Eze South'),
  ('Enugu', 'Isi Uzo'),
  ('Enugu', 'Nkanu East'),
  ('Enugu', 'Nkanu West'),
  ('Enugu', 'Nsukka'),
  ('Enugu', 'Oji River'),
  ('Enugu', 'Udenu'),
  ('Enugu', 'Udi'),
  ('Enugu', 'Uzo Uwani'),
  ('FCT', 'Abaji'),
  ('FCT', 'Bwari'),
  ('FCT', 'Gwagwalada'),
  ('FCT', 'Kuje'),
  ('FCT', 'Kwali'),
  ('FCT', 'Municipal Area Council'),
  ('Gombe', 'Akko'),
  ('Gombe', 'Balanga'),
  ('Gombe', 'Billiri'),
  ('Gombe', 'Dukku'),
  ('Gombe', 'Funakaye'),
  ('Gombe', 'Gombe'),
  ('Gombe', 'Kaltungo'),
  ('Gombe', 'Kwami'),
  ('Gombe', 'Nafada'),
  ('Gombe', 'Shongom'),
  ('Gombe', 'Yamaltu/Deba'),
  ('Imo', 'Aboh Mbaise'),
  ('Imo', 'Ahiazu Mbaise'),
  ('Imo', 'Ehime Mbano'),
  ('Imo', 'Ezinihitte'),
  ('Imo', 'Ideato North'),
  ('Imo', 'Ideato South'),
  ('Imo', 'Ihitte/Uboma'),
  ('Imo', 'Ikeduru'),
  ('Imo', 'Isiala Mbano'),
  ('Imo', 'Isu'),
  ('Imo', 'Mbaitoli'),
  ('Imo', 'Ngor Okpala'),
  ('Imo', 'Njaba'),
  ('Imo', 'Nkwerre'),
  ('Imo', 'Nwangele'),
  ('Imo', 'Obowo'),
  ('Imo', 'Oguta'),
  ('Imo', 'Ohaji/Egbema'),
  ('Imo', 'Okigwe'),
  ('Imo', 'Orlu'),
  ('Imo', 'Orsu'),
  ('Imo', 'Oru East'),
  ('Imo', 'Oru West'),
  ('Imo', 'Owerri Municipal'),
  ('Imo', 'Owerri North'),
  ('Imo', 'Owerri West'),
  ('Imo', 'Unuimo'),
  ('Jigawa', 'Auyo'),
  ('Jigawa', 'Babura'),
  ('Jigawa', 'Biriniwa'),
  ('Jigawa', 'Birnin Kudu'),
  ('Jigawa', 'Buji'),
  ('Jigawa', 'Dutse'),
  ('Jigawa', 'Gagarawa'),
  ('Jigawa', 'Garki'),
  ('Jigawa', 'Gumel'),
  ('Jigawa', 'Guri'),
  ('Jigawa', 'Gwaram'),
  ('Jigawa', 'Gwiwa'),
  ('Jigawa', 'Hadejia'),
  ('Jigawa', 'Jahun'),
  ('Jigawa', 'Kafin Hausa'),
  ('Jigawa', 'Kazaure'),
  ('Jigawa', 'Kiri Kasama'),
  ('Jigawa', 'Kiyawa'),
  ('Jigawa', 'Kaugama'),
  ('Jigawa', 'Maigatari'),
  ('Jigawa', 'Malam Madori'),
  ('Jigawa', 'Miga'),
  ('Jigawa', 'Ringim'),
  ('Jigawa', 'Roni'),
  ('Jigawa', 'Sule Tankarkar'),
  ('Jigawa', 'Taura'),
  ('Jigawa', 'Yankwashi'),
  ('Kaduna', 'Birnin Gwari'),
  ('Kaduna', 'Chikun'),
  ('Kaduna', 'Giwa'),
  ('Kaduna', 'Igabi'),
  ('Kaduna', 'Ikara'),
  ('Kaduna', 'Jaba'),
  ('Kaduna', 'Jema''a'),
  ('Kaduna', 'Kachia'),
  ('Kaduna', 'Kaduna North'),
  ('Kaduna', 'Kaduna South'),
  ('Kaduna', 'Kagarko'),
  ('Kaduna', 'Kajuru'),
  ('Kaduna', 'Kaura'),
  ('Kaduna', 'Kauru'),
  ('Kaduna', 'Kubau'),
  ('Kaduna', 'Kudan'),
  ('Kaduna', 'Lere'),
  ('Kaduna', 'Makarfi'),
  ('Kaduna', 'Sabon Gari'),
  ('Kaduna', 'Sanga'),
  ('Kaduna', 'Soba'),
  ('Kaduna', 'Zangon Kataf'),
  ('Kaduna', 'Zaria'),
  ('Kano', 'Ajingi'),
  ('Kano', 'Albasu'),
  ('Kano', 'Bagwai'),
  ('Kano', 'Bebeji'),
  ('Kano', 'Bichi'),
  ('Kano', 'Bunkure'),
  ('Kano', 'Dala'),
  ('Kano', 'Dambatta'),
  ('Kano', 'Dawakin Kudu'),
  ('Kano', 'Dawakin Tofa'),
  ('Kano', 'Doguwa'),
  ('Kano', 'Fagge'),
  ('Kano', 'Gabasawa'),
  ('Kano', 'Garko'),
  ('Kano', 'Garun Mallam'),
  ('Kano', 'Gaya'),
  ('Kano', 'Gezawa'),
  ('Kano', 'Gwale'),
  ('Kano', 'Gwarzo'),
  ('Kano', 'Kabo'),
  ('Kano', 'Kano Municipal'),
  ('Kano', 'Karaye'),
  ('Kano', 'Kibiya'),
  ('Kano', 'Kiru'),
  ('Kano', 'Kumbotso'),
  ('Kano', 'Kunchi'),
  ('Kano', 'Kura'),
  ('Kano', 'Madobi'),
  ('Kano', 'Makoda'),
  ('Kano', 'Minjibir'),
  ('Kano', 'Nasarawa'),
  ('Kano', 'Rano'),
  ('Kano', 'Rimin Gado'),
  ('Kano', 'Rogo'),
  ('Kano', 'Shanono'),
  ('Kano', 'Sumaila'),
  ('Kano', 'Takai'),
  ('Kano', 'Tarauni'),
  ('Kano', 'Tofa'),
  ('Kano', 'Tsanyawa'),
  ('Kano', 'Tudun Wada'),
  ('Kano', 'Ungogo'),
  ('Kano', 'Warawa'),
  ('Kano', 'Wudil'),
  ('Katsina', 'Bakori'),
  ('Katsina', 'Batagarawa'),
  ('Katsina', 'Batsari'),
  ('Katsina', 'Baure'),
  ('Katsina', 'Bindawa'),
  ('Katsina', 'Charanchi'),
  ('Katsina', 'Dandume'),
  ('Katsina', 'Danja'),
  ('Katsina', 'Dan Musa'),
  ('Katsina', 'Daura'),
  ('Katsina', 'Dutsi'),
  ('Katsina', 'Dutsin Ma'),
  ('Katsina', 'Faskari'),
  ('Katsina', 'Funtua'),
  ('Katsina', 'Ingawa'),
  ('Katsina', 'Jibia'),
  ('Katsina', 'Kafur'),
  ('Katsina', 'Kaita'),
  ('Katsina', 'Kankara'),
  ('Katsina', 'Kankia'),
  ('Katsina', 'Katsina'),
  ('Katsina', 'Kurfi'),
  ('Katsina', 'Kusada'),
  ('Katsina', 'Mai''Adua'),
  ('Katsina', 'Malumfashi'),
  ('Katsina', 'Mani'),
  ('Katsina', 'Mashi'),
  ('Katsina', 'Matazu'),
  ('Katsina', 'Musawa'),
  ('Katsina', 'Rimi'),
  ('Katsina', 'Sabuwa'),
  ('Katsina', 'Safana'),
  ('Katsina', 'Sandamu'),
  ('Katsina', 'Zango'),
  ('Kebbi', 'Aleiro'),
  ('Kebbi', 'Arewa Dandi'),
  ('Kebbi', 'Argungu'),
  ('Kebbi', 'Augie'),
  ('Kebbi', 'Bagudo'),
  ('Kebbi', 'Birnin Kebbi'),
  ('Kebbi', 'Bunza'),
  ('Kebbi', 'Dandi'),
  ('Kebbi', 'Fakai'),
  ('Kebbi', 'Gwandu'),
  ('Kebbi', 'Jega'),
  ('Kebbi', 'Kalgo'),
  ('Kebbi', 'Koko/Besse'),
  ('Kebbi', 'Maiyama'),
  ('Kebbi', 'Ngaski'),
  ('Kebbi', 'Sakaba'),
  ('Kebbi', 'Shanga'),
  ('Kebbi', 'Suru'),
  ('Kebbi', 'Wasagu/Danko'),
  ('Kebbi', 'Yauri'),
  ('Kebbi', 'Zuru'),
  ('Kogi', 'Adavi'),
  ('Kogi', 'Ajaokuta'),
  ('Kogi', 'Ankpa'),
  ('Kogi', 'Bassa'),
  ('Kogi', 'Dekina'),
  ('Kogi', 'Ibaji'),
  ('Kogi', 'Idah'),
  ('Kogi', 'Igalamela Odolu'),
  ('Kogi', 'Ijumu'),
  ('Kogi', 'Kabba/Bunu'),
  ('Kogi', 'Kogi'),
  ('Kogi', 'Lokoja'),
  ('Kogi', 'Mopa Muro'),
  ('Kogi', 'Ofu'),
  ('Kogi', 'Ogori/Magongo'),
  ('Kogi', 'Okehi'),
  ('Kogi', 'Okene'),
  ('Kogi', 'Olamaboro'),
  ('Kogi', 'Omala'),
  ('Kogi', 'Yagba East'),
  ('Kogi', 'Yagba West'),
  ('Kwara', 'Asa'),
  ('Kwara', 'Baruten'),
  ('Kwara', 'Edu'),
  ('Kwara', 'Ekiti'),
  ('Kwara', 'Ifelodun'),
  ('Kwara', 'Ilorin East'),
  ('Kwara', 'Ilorin South'),
  ('Kwara', 'Ilorin West'),
  ('Kwara', 'Irepodun'),
  ('Kwara', 'Isin'),
  ('Kwara', 'Kaiama'),
  ('Kwara', 'Moro'),
  ('Kwara', 'Offa'),
  ('Kwara', 'Oke Ero'),
  ('Kwara', 'Oyun'),
  ('Kwara', 'Pategi'),
  ('Lagos', 'Agege'),
  ('Lagos', 'Ajeromi-Ifelodun'),
  ('Lagos', 'Alimosho'),
  ('Lagos', 'Amuwo-Odofin'),
  ('Lagos', 'Apapa'),
  ('Lagos', 'Badagry'),
  ('Lagos', 'Epe'),
  ('Lagos', 'Eti Osa'),
  ('Lagos', 'Ibeju-Lekki'),
  ('Lagos', 'Ifako-Ijaiye'),
  ('Lagos', 'Ikeja'),
  ('Lagos', 'Ikorodu'),
  ('Lagos', 'Kosofe'),
  ('Lagos', 'Lagos Island'),
  ('Lagos', 'Lagos Mainland'),
  ('Lagos', 'Mushin'),
  ('Lagos', 'Ojo'),
  ('Lagos', 'Oshodi-Isolo'),
  ('Lagos', 'Shomolu'),
  ('Lagos', 'Surulere'),
  ('Nasarawa', 'Akwanga'),
  ('Nasarawa', 'Awe'),
  ('Nasarawa', 'Doma'),
  ('Nasarawa', 'Karu'),
  ('Nasarawa', 'Keana'),
  ('Nasarawa', 'Keffi'),
  ('Nasarawa', 'Kokona'),
  ('Nasarawa', 'Lafia'),
  ('Nasarawa', 'Nasarawa'),
  ('Nasarawa', 'Nasarawa Egon'),
  ('Nasarawa', 'Obi'),
  ('Nasarawa', 'Toto'),
  ('Nasarawa', 'Wamba'),
  ('Niger', 'Agaie'),
  ('Niger', 'Agwara'),
  ('Niger', 'Bida'),
  ('Niger', 'Borgu'),
  ('Niger', 'Bosso'),
  ('Niger', 'Chanchaga'),
  ('Niger', 'Edati'),
  ('Niger', 'Gbako'),
  ('Niger', 'Gurara'),
  ('Niger', 'Katcha'),
  ('Niger', 'Kontagora'),
  ('Niger', 'Lapai'),
  ('Niger', 'Lavun'),
  ('Niger', 'Magama'),
  ('Niger', 'Mariga'),
  ('Niger', 'Mashegu'),
  ('Niger', 'Mokwa'),
  ('Niger', 'Moya'),
  ('Niger', 'Paikoro'),
  ('Niger', 'Rafi'),
  ('Niger', 'Rijau'),
  ('Niger', 'Shiroro'),
  ('Niger', 'Suleja'),
  ('Niger', 'Tafa'),
  ('Niger', 'Wushishi'),
  ('Ogun', 'Abeokuta North'),
  ('Ogun', 'Abeokuta South'),
  ('Ogun', 'Ado-Odo/Ota'),
  ('Ogun', 'Egbado North'),
  ('Ogun', 'Egbado South'),
  ('Ogun', 'Ewekoro'),
  ('Ogun', 'Ifo'),
  ('Ogun', 'Ijebu East'),
  ('Ogun', 'Ijebu North'),
  ('Ogun', 'Ijebu North East'),
  ('Ogun', 'Ijebu Ode'),
  ('Ogun', 'Ikenne'),
  ('Ogun', 'Imeko Afon'),
  ('Ogun', 'Ipokia'),
  ('Ogun', 'Obafemi Owode'),
  ('Ogun', 'Odeda'),
  ('Ogun', 'Odogbolu'),
  ('Ogun', 'Ogun Waterside'),
  ('Ogun', 'Remo North'),
  ('Ogun', 'Shagamu'),
  ('Ondo', 'Akoko North-East'),
  ('Ondo', 'Akoko North-West'),
  ('Ondo', 'Akoko South-West'),
  ('Ondo', 'Akoko South-East'),
  ('Ondo', 'Akure North'),
  ('Ondo', 'Akure South'),
  ('Ondo', 'Ese Odo'),
  ('Ondo', 'Idanre'),
  ('Ondo', 'Ifedore'),
  ('Ondo', 'Ilaje'),
  ('Ondo', 'Ile Oluji/Okeigbo'),
  ('Ondo', 'Irele'),
  ('Ondo', 'Odigbo'),
  ('Ondo', 'Okitipupa'),
  ('Ondo', 'Ondo East'),
  ('Ondo', 'Ondo West'),
  ('Ondo', 'Ose'),
  ('Ondo', 'Owo'),
  ('Osun', 'Atakunmosa East'),
  ('Osun', 'Atakunmosa West'),
  ('Osun', 'Aiyedaade'),
  ('Osun', 'Aiyedire'),
  ('Osun', 'Boluwaduro'),
  ('Osun', 'Boripe'),
  ('Osun', 'Ede North'),
  ('Osun', 'Ede South'),
  ('Osun', 'Efe'),
  ('Osun', 'Ejigbo'),
  ('Osun', 'Ifedayo'),
  ('Osun', 'Ifelodun'),
  ('Osun', 'Ila'),
  ('Osun', 'Ilesa East'),
  ('Osun', 'Ilesa West'),
  ('Osun', 'Irepodun'),
  ('Osun', 'Irewole'),
  ('Osun', 'Isokan'),
  ('Osun', 'Iwo'),
  ('Osun', 'Obokun'),
  ('Osun', 'Odo Otin'),
  ('Osun', 'Ola Oluwa'),
  ('Osun', 'Olorunda'),
  ('Osun', 'Oriade'),
  ('Osun', 'Orolu'),
  ('Osun', 'Osogbo'),
  ('Oyo', 'Afijio'),
  ('Oyo', 'Akinyele'),
  ('Oyo', 'Atiba'),
  ('Oyo', 'Atisbo'),
  ('Oyo', 'Egbeda'),
  ('Oyo', 'Ibadan North'),
  ('Oyo', 'Ibadan North-East'),
  ('Oyo', 'Ibadan North-West'),
  ('Oyo', 'Ibadan South-East'),
  ('Oyo', 'Ibadan South-West'),
  ('Oyo', 'Ibarapa Central'),
  ('Oyo', 'Ibarapa East'),
  ('Oyo', 'Ibarapa North'),
  ('Oyo', 'Ido'),
  ('Oyo', 'Irepo'),
  ('Oyo', 'Iseyin'),
  ('Oyo', 'Itesiwaju'),
  ('Oyo', 'Iwajowa'),
  ('Oyo', 'Kajola'),
  ('Oyo', 'Lagelu'),
  ('Oyo', 'Ogbomosho North'),
  ('Oyo', 'Ogbomosho South'),
  ('Oyo', 'Ogo Oluwa'),
  ('Oyo', 'Olorunsogo'),
  ('Oyo', 'Oluyole'),
  ('Oyo', 'Ona Ara'),
  ('Oyo', 'Orelope'),
  ('Oyo', 'Ori Ire'),
  ('Oyo', 'Oyo East'),
  ('Oyo', 'Oyo West'),
  ('Oyo', 'Saki East'),
  ('Oyo', 'Saki West'),
  ('Oyo', 'Surulere'),
  ('Plateau', 'Bokkos'),
  ('Plateau', 'Barkin Ladi'),
  ('Plateau', 'Bassa'),
  ('Plateau', 'Jos East'),
  ('Plateau', 'Jos North'),
  ('Plateau', 'Jos South'),
  ('Plateau', 'Kanam'),
  ('Plateau', 'Kanke'),
  ('Plateau', 'Langtang North'),
  ('Plateau', 'Langtang South'),
  ('Plateau', 'Mangu'),
  ('Plateau', 'Mikang'),
  ('Plateau', 'Pankshin'),
  ('Plateau', 'Qua''an Pan'),
  ('Plateau', 'Riyom'),
  ('Plateau', 'Shendam'),
  ('Plateau', 'Wase'),
  ('Rivers', 'Abua/Odual'),
  ('Rivers', 'Ahoada East'),
  ('Rivers', 'Ahoada West'),
  ('Rivers', 'Akuku-Toru'),
  ('Rivers', 'Andoni'),
  ('Rivers', 'Asari-Toru'),
  ('Rivers', 'Bonny'),
  ('Rivers', 'Degema'),
  ('Rivers', 'Eleme'),
  ('Rivers', 'Emohua'),
  ('Rivers', 'Etche'),
  ('Rivers', 'Gokana'),
  ('Rivers', 'Ikwerre'),
  ('Rivers', 'Khana'),
  ('Rivers', 'Obio/Akpor'),
  ('Rivers', 'Ogba/Egbema/Ndoni'),
  ('Rivers', 'Ogu/Bolo'),
  ('Rivers', 'Okrika'),
  ('Rivers', 'Omuma'),
  ('Rivers', 'Opobo/Nkoro'),
  ('Rivers', 'Oyigbo'),
  ('Rivers', 'Port Harcourt'),
  ('Rivers', 'Tai'),
  ('Sokoto', 'Binji'),
  ('Sokoto', 'Bodinga'),
  ('Sokoto', 'Dange Shuni'),
  ('Sokoto', 'Gada'),
  ('Sokoto', 'Goronyo'),
  ('Sokoto', 'Gudu'),
  ('Sokoto', 'Gwadabawa'),
  ('Sokoto', 'Illela'),
  ('Sokoto', 'Isa'),
  ('Sokoto', 'Kebbe'),
  ('Sokoto', 'Kware'),
  ('Sokoto', 'Rabah'),
  ('Sokoto', 'Sabon Birni'),
  ('Sokoto', 'Shagari'),
  ('Sokoto', 'Silame'),
  ('Sokoto', 'Sokoto North'),
  ('Sokoto', 'Sokoto South'),
  ('Sokoto', 'Tambuwal'),
  ('Sokoto', 'Tangaza'),
  ('Sokoto', 'Tureta'),
  ('Sokoto', 'Wamako'),
  ('Sokoto', 'Wurno'),
  ('Sokoto', 'Yabo'),
  ('Taraba', 'Ardo Kola'),
  ('Taraba', 'Bali'),
  ('Taraba', 'Donga'),
  ('Taraba', 'Gashaka'),
  ('Taraba', 'Gassol'),
  ('Taraba', 'Ibi'),
  ('Taraba', 'Jalingo'),
  ('Taraba', 'Karim Lamido'),
  ('Taraba', 'Kumi'),
  ('Taraba', 'Lau'),
  ('Taraba', 'Sardauna'),
  ('Taraba', 'Takum'),
  ('Taraba', 'Ussa'),
  ('Taraba', 'Wukari'),
  ('Taraba', 'Yorro'),
  ('Taraba', 'Zing'),
  ('Yobe', 'Bade'),
  ('Yobe', 'Bursari'),
  ('Yobe', 'Damaturu'),
  ('Yobe', 'Fika'),
  ('Yobe', 'Fune'),
  ('Yobe', 'Geidam'),
  ('Yobe', 'Gujba'),
  ('Yobe', 'Gulani'),
  ('Yobe', 'Jakusko'),
  ('Yobe', 'Karasuwa'),
  ('Yobe', 'Machina'),
  ('Yobe', 'Nangere'),
  ('Yobe', 'Nguru'),
  ('Yobe', 'Potiskum'),
  ('Yobe', 'Tarmuwa'),
  ('Yobe', 'Yunusari'),
  ('Yobe', 'Yusufari'),
  ('Zamfara', 'Anka'),
  ('Zamfara', 'Bakura'),
  ('Zamfara', 'Birnin Magaji/Kiyaw'),
  ('Zamfara', 'Bukkuyum'),
  ('Zamfara', 'Bungudu'),
  ('Zamfara', 'Gummi'),
  ('Zamfara', 'Gusau'),
  ('Zamfara', 'Kaura Namoda'),
  ('Zamfara', 'Maradun'),
  ('Zamfara', 'Maru'),
  ('Zamfara', 'Shinkafi'),
  ('Zamfara', 'Talata Mafara'),
  ('Zamfara', 'Chafe'),
  ('Zamfara', 'Zurmi');

-- Reference data: readable by every signed-in client (and anon, like the rest
-- of the location data the app ships), writable only by the service role.
alter table public.nigeria_states enable row level security;
alter table public.nigeria_lgas enable row level security;
revoke insert, update, delete on public.nigeria_states, public.nigeria_lgas from anon, authenticated;
create policy nigeria_states_select on public.nigeria_states for select to anon, authenticated using (true);
create policy nigeria_lgas_select on public.nigeria_lgas for select to anon, authenticated using (true);

comment on table public.nigeria_states is
  'The 36 states + FCT, canonical spellings. Seeded from lib/core/data/nigeria_locations_data.dart; read-only to clients.';
comment on table public.nigeria_lgas is
  'The 770 LGAs by state, canonical spellings. Seeded from lib/core/data/nigeria_locations_data.dart; read-only to clients. alerts.target_state / target_lga are foreign keys into it.';

-- ── Pre-existing alerts ─────────────────────────────────────────────────────
--
-- The rule, in order. Nothing here ever widens an alert's audience: a target
-- is only ever canonicalised, narrowed to the one state it can mean, or the
-- alert is set aside.
--
--   1. 'all' / ' All ' in target_lga is normalised to 'All', and a state that
--      is a known state under a different casing/padding is canonicalised.
--   2. A (state, LGA) pair that matches a real pair case-insensitively is
--      rewritten to the canonical spelling of both.
--   3. An alert with an LGA and no state whose LGA name belongs to exactly one
--      state adopts that state (this is 20260927070000's backfill again, now
--      driven from the table above, so it also catches casing variants).
--   4. Anything still unresolvable — an ambiguous LGA name with no state, an
--      LGA that is in no state at all, an unknown state — is COPIED to
--      public.alerts_unresolved_target with the reason and DELETED from
--      public.alerts, and the migration raises a WARNING naming each one.
--      Deleting is the only non-widening option left: the row cannot be kept
--      (it cannot satisfy the constraint), and the alternatives — blanking the
--      LGA, or setting target_lga = 'All' — would turn an alert meant for one
--      LGA into one for a whole state or the whole country. The alert is kept
--      verbatim in the quarantine table so an admin can read it and re-issue
--      it with the right state.
--
-- The live database has no alerts at all at the time of writing, so on it
-- every step below is a no-op; the steps exist for any other deployment.
--
-- Safety: alerts only queue a notification_outbox row from the AFTER INSERT
-- trigger alerts_after_insert, so these UPDATEs and DELETEs send no push. The
-- BEFORE UPDATE triggers are alerts_touch (bumps updated_at) and
-- alerts_guard_author (rejects a change of created_by, untouched here).

create table public.alerts_unresolved_target (
  id            uuid primary key,
  title         text not null,
  message       text not null default '',
  severity      text not null default 'info',
  target_lga    text,
  target_state  text,
  report_id     uuid,
  created_by    uuid,
  is_active     boolean not null default false,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  reason        text not null,
  quarantined_at timestamptz not null default now()
);

-- Not a client table: it holds alerts that were removed, and is read from the
-- SQL editor (service role) when the WARNING below fires.
alter table public.alerts_unresolved_target enable row level security;
revoke all on public.alerts_unresolved_target from anon, authenticated;

comment on table public.alerts_unresolved_target is
  'Alerts removed by 20260927080000 because their target could not be resolved to one (state, LGA). Kept verbatim so an admin can re-issue them with a state. Service role only.';

-- 1. Normalise the 'All' sentinel and the state spelling.
update public.alerts
   set target_lga = 'All'
 where lower(btrim(target_lga)) = 'all'
   and target_lga <> 'All';

update public.alerts a
   set target_state = s.name
  from public.nigeria_states s
 where a.target_state is not null
   and lower(btrim(a.target_state)) = lower(s.name)
   and a.target_state <> s.name;

-- 2. Canonicalise a (state, LGA) pair that is real apart from case/padding.
update public.alerts a
   set target_state = l.state,
       target_lga   = l.lga
  from public.nigeria_lgas l
 where a.target_state is not null
   and lower(btrim(a.target_lga)) <> 'all'
   and lower(btrim(a.target_state)) = lower(l.state)
   and lower(btrim(a.target_lga)) = lower(l.lga)
   and (a.target_state, a.target_lga) is distinct from (l.state, l.lga);

-- 3. An LGA name that belongs to exactly one state fixes its own state.
update public.alerts a
   set target_state = u.state,
       target_lga   = u.lga
  from (
    select lower(lga) as key, min(state) as state, min(lga) as lga
      from public.nigeria_lgas
     group by lower(lga)
    having count(*) = 1
  ) u
 where a.target_state is null
   and lower(btrim(a.target_lga)) = u.key;

-- 4. Set aside whatever is left, loudly.
with unresolved as (
  select a.*,
         case
           when a.target_state is not null
             and not exists (select 1 from public.nigeria_states s where s.name = a.target_state)
             then format('target_state %L is not a Nigerian state', a.target_state)
           when a.target_state is null and exists (
                  select 1 from public.nigeria_lgas l where lower(l.lga) = lower(btrim(a.target_lga)))
             then format('target_lga %L is an LGA of more than one state and the alert names none', a.target_lga)
           when a.target_state is null
             then format('target_lga %L is not an LGA of any state and the alert names no state', a.target_lga)
           else format('%L is not an LGA of %L', a.target_lga, a.target_state)
         end as reason
    from public.alerts a
   where (a.target_state is null and lower(btrim(a.target_lga)) <> 'all')
      or (a.target_state is not null
          and not exists (select 1 from public.nigeria_states s where s.name = a.target_state))
      or (a.target_state is not null
          and lower(btrim(a.target_lga)) <> 'all'
          and not exists (select 1 from public.nigeria_lgas l
                           where l.state = a.target_state and l.lga = btrim(a.target_lga)))
)
insert into public.alerts_unresolved_target
  (id, title, message, severity, target_lga, target_state, report_id, created_by,
   is_active, created_at, updated_at, reason)
select id, title, message, severity, target_lga, target_state, report_id, created_by,
       is_active, created_at, updated_at, reason
  from unresolved;

delete from public.alerts a
 using public.alerts_unresolved_target q
 where q.id = a.id;

do $$
declare
  n bigint;
  r record;
begin
  select count(*) into n from public.alerts_unresolved_target;
  if n > 0 then
    raise warning 'alert_state_required: % alert(s) had a target that cannot be resolved to one (state, LGA). They were moved to public.alerts_unresolved_target and removed from public.alerts. Re-issue each one with a state:', n;
    for r in select id, title, target_lga, target_state, reason
               from public.alerts_unresolved_target order by created_at loop
      raise warning '  alert % (%): % [target_lga=%, target_state=%]',
        r.id, r.title, r.reason, r.target_lga, coalesce(r.target_state, 'NULL');
    end loop;
  end if;
end $$;

-- ── The constraint ──────────────────────────────────────────────────────────
--
-- target_lga_canonical is target_lga with 'All' (in any casing) collapsed to
-- NULL, so the composite foreign key below is simply not checked for an
-- "every LGA" alert (MATCH SIMPLE: a partly-NULL key passes). It exists only
-- to carry that foreign key; nothing reads it, and nothing writes it.

alter table public.alerts add column target_lga_canonical text
  generated always as (
    case when lower(btrim(target_lga)) = 'all' then null else btrim(target_lga) end
  ) stored;

-- The structural rule, independent of the reference tables: naming an LGA
-- means naming its state. Only 'All' may stand alone.
alter table public.alerts add constraint alerts_target_lga_needs_state
  check (target_state is not null or lower(btrim(target_lga)) = 'all');

-- The state must be a real state...
alter table public.alerts add constraint alerts_target_state_fkey
  foreign key (target_state) references public.nigeria_states (name);

-- ...and a named LGA must be one of that state's. (No ON UPDATE action: a
-- generated column may not take one, and renaming canonical reference data
-- should be a deliberate migration that updates the alerts too, not a silent
-- cascade.)
alter table public.alerts add constraint alerts_target_lga_fkey
  foreign key (target_state, target_lga_canonical)
  references public.nigeria_lgas (state, lga);

comment on column public.alerts.target_state is
  'State the alert targets: every LGA of it when target_lga = ''All'', otherwise the state target_lga belongs to. NULL only with target_lga = ''All'' (everyone, everywhere) — an LGA without a state is rejected by alerts_target_lga_needs_state.';
comment on column public.alerts.target_lga is
  'LGA the alert targets, spelled as in public.nigeria_lgas, or ''All'' for every LGA of target_state (or everyone when target_state is NULL).';
comment on column public.alerts.target_lga_canonical is
  'Generated: btrim(target_lga), or NULL when target_lga is ''All''. Exists only to carry alerts_target_lga_fkey; do not read or write it.';


-- ============================================================================
-- SOURCE: supabase/migrations/20260927090000_authority_state_required.sql
-- ============================================================================

-- Every SMS authority must name the state of the LGA it covers.
--
-- 20260927030000 added authorities.coverage_state but left it nullable, and
-- backend/src/repo.js findAuthorities() matched
--
--   coverage_lga = report.lga and (coverage_state = report.state or coverage_state is null)
--
-- so a contact whose coverage_state was never filled in was texted for its LGA
-- name in EVERY state. 6 of the 770 LGA names are not unique, so for those a
-- single contact silently covered two different places:
--
--   Bassa      Kogi, Plateau      Nasarawa   Kano, Nasarawa
--   Ifelodun   Kwara, Osun        Obi        Benue, Nasarawa
--   Irepodun   Kwara, Osun        Surulere   Lagos, Oyo
--
-- A contact for "Bassa" with no state was texted about incidents in Kogi AND
-- in Plateau — two places ~500 km apart. From here on the database rejects
-- that shape outright: coverage_state is NOT NULL, and (coverage_state,
-- coverage_lga) must be a real pair in public.nigeria_lgas.
--
-- This is the same treatment 20260927080000 gave alerts.target_state, using
-- the two reference tables that migration created (public.nigeria_states,
-- public.nigeria_lgas, seeded from lib/core/data/nigeria_locations_data.dart
-- and client-read-only). It is simpler here because authorities has NO 'All'
-- sentinel: coverage_lga is always one concrete LGA. The admin panel
-- (CRADI-Mobile-Admin app/dashboard/authorities/page.tsx) only ever offers
-- LGAs from the fixed per-state list, the backend only ever compares it for
-- equality with reports.lga, and the import tool
-- (migration/firebase-to-supabase/src/transform.js transformAuthority) only
-- ever writes a concrete LGA — so no generated "canonical" column and no
-- partial-key foreign key are needed; a plain composite FK does the job.
--
-- On a database where public.authorities is empty every step below is a
-- no-op: the UPDATEs match nothing, the quarantine table stays empty, no
-- WARNING is raised, and only the NOT NULL / foreign keys at the end take
-- effect.

-- ── Pre-existing authorities ────────────────────────────────────────────────
--
-- The rule, in order. Nothing here ever widens a contact's coverage: it is
-- only ever canonicalised, narrowed to the one state it can mean, or the row
-- is set aside. Nothing is silently dropped.
--
--   1. A coverage_state that is a known state under a different casing or
--      with padding is canonicalised ('  benue ' -> 'Benue').
--   2. A (state, LGA) pair that matches a real pair case-insensitively is
--      rewritten to the canonical spelling of both (' obi ' in 'BENUE' ->
--      'Obi' in 'Benue').
--   3. A contact with no state whose LGA name belongs to exactly one state
--      adopts that state. This is the only safe inference: 764 of the 770
--      names identify one place, so the contact already covered exactly that
--      place and nothing changes about who it is texted for.
--   4. Anything still unresolvable — an ambiguous LGA name with no state, an
--      LGA that is in no state at all, an unknown state, an LGA that is not
--      in the state the row claims — is COPIED VERBATIM into
--      public.authorities_unresolved_coverage with a per-row reason, DELETED
--      from public.authorities, and named in a WARNING.
--
--      Deleting is the only non-widening option left: the row cannot stay
--      (it cannot satisfy the constraint), and every alternative is worse —
--      picking one of the candidate states would text the wrong emergency
--      desk about incidents in a state it does not serve, and there is no
--      "all states" value to fall back to. The contact is kept in full, phone
--      number included, so an operator can put it back with the right state.

create table public.authorities_unresolved_coverage (
  id             uuid primary key,
  name           text not null default '',
  organization   text,
  phone          text not null,
  coverage_lga   text not null,
  coverage_state text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  reason         text not null,
  quarantined_at timestamptz not null default now()
);

-- NOT a client table, and NOT a place to leave data lying around.
--
-- Unlike alerts (public broadcasts), authorities rows are real operational
-- contact details — the names and mobile numbers of emergency desks and
-- officers. This table holds the ones this migration had to remove because
-- their coverage could not be resolved to one (state, LGA). It is readable
-- only by the service role (the dashboard SQL editor); anon and authenticated
-- have no grants at all, and RLS is on with no policy, so even a leaked
-- client key cannot read a single row.
--
-- RECOVERY PROCEDURE — do this as soon as the migration warns, because every
-- row here is an emergency contact that is NO LONGER BEING TEXTED:
--
--   1. List what was set aside (SQL editor, service role):
--
--        select id, name, organization, phone, coverage_lga, coverage_state, reason
--          from public.authorities_unresolved_coverage
--         order by quarantined_at;
--
--   2. For each row, decide which state that contact actually serves — ask
--      the desk if you have to. Never guess: texting the wrong state's desk
--      is the failure this migration exists to prevent.
--
--   3. Re-add it in the admin panel (Admin -> Authorities -> Add Authority),
--      choosing the LGA under its state, or insert it directly:
--
--        insert into public.authorities (name, organization, phone, coverage_lga, coverage_state)
--        values ('Bassa Emergency Desk', 'SEMA Plateau', '+2348031234567', 'Bassa', 'Plateau');
--
--   4. Delete the row from this table once it has been re-added. When the
--      table is empty it can be dropped in a later migration. Do not leave
--      personal phone numbers in a table nothing reads.
alter table public.authorities_unresolved_coverage enable row level security;
revoke all on public.authorities_unresolved_coverage from anon, authenticated;

comment on table public.authorities_unresolved_coverage is
  'SMS contacts removed by 20260927090000 because their coverage could not be resolved to one (state, LGA). Holds real names and phone numbers, verbatim, so an operator can re-add each one with the right state and then delete it from here. Service role only; see the migration for the recovery procedure. Rows here are NOT being texted.';

-- 1. Canonicalise the state spelling.
update public.authorities a
   set coverage_state = s.name
  from public.nigeria_states s
 where a.coverage_state is not null
   and lower(btrim(a.coverage_state)) = lower(s.name)
   and a.coverage_state <> s.name;

-- 2. Canonicalise a (state, LGA) pair that is real apart from case/padding.
update public.authorities a
   set coverage_state = l.state,
       coverage_lga   = l.lga
  from public.nigeria_lgas l
 where a.coverage_state is not null
   and lower(btrim(a.coverage_state)) = lower(l.state)
   and lower(btrim(a.coverage_lga)) = lower(l.lga)
   and (a.coverage_state, a.coverage_lga) is distinct from (l.state, l.lga);

-- 3. An LGA name that belongs to exactly one state fixes its own state.
update public.authorities a
   set coverage_state = u.state,
       coverage_lga   = u.lga
  from (
    select lower(lga) as key, min(state) as state, min(lga) as lga
      from public.nigeria_lgas
     group by lower(lga)
    having count(*) = 1
  ) u
 where a.coverage_state is null
   and lower(btrim(a.coverage_lga)) = u.key;

-- 4. Set aside whatever is left, loudly.
with unresolved as (
  select a.*,
         case
           when a.coverage_state is not null
             and not exists (select 1 from public.nigeria_states s where s.name = a.coverage_state)
             then format('coverage_state %L is not a Nigerian state', a.coverage_state)
           when a.coverage_state is null and exists (
                  select 1 from public.nigeria_lgas l where lower(l.lga) = lower(btrim(a.coverage_lga)))
             then format('coverage_lga %L is an LGA of more than one state (%s) and the contact names none',
                         a.coverage_lga,
                         (select string_agg(l.state, ', ' order by l.state)
                            from public.nigeria_lgas l where lower(l.lga) = lower(btrim(a.coverage_lga))))
           when a.coverage_state is null
             then format('coverage_lga %L is not an LGA of any state and the contact names no state', a.coverage_lga)
           else format('%L is not an LGA of %L', a.coverage_lga, a.coverage_state)
         end as reason
    from public.authorities a
   where a.coverage_state is null
      or not exists (select 1 from public.nigeria_states s where s.name = a.coverage_state)
      or not exists (select 1 from public.nigeria_lgas l
                      where l.state = a.coverage_state and l.lga = btrim(a.coverage_lga))
)
insert into public.authorities_unresolved_coverage
  (id, name, organization, phone, coverage_lga, coverage_state, created_at, updated_at, reason)
select id, name, organization, phone, coverage_lga, coverage_state, created_at, updated_at, reason
  from unresolved;

delete from public.authorities a
 using public.authorities_unresolved_coverage q
 where q.id = a.id;

do $$
declare
  n bigint;
  r record;
begin
  select count(*) into n from public.authorities_unresolved_coverage;
  if n > 0 then
    raise warning 'authority_state_required: % SMS contact(s) cover an LGA that cannot be resolved to one state. They were copied to public.authorities_unresolved_coverage and removed from public.authorities, and are NO LONGER BEING TEXTED. Re-add each one with the right state (admin panel -> Authorities), then delete it from that table:', n;
    for r in select id, name, organization, phone, coverage_lga, coverage_state, reason
               from public.authorities_unresolved_coverage order by created_at loop
      raise warning '  authority % (% / %, phone %): covers % in % -- %',
        r.id,
        coalesce(nullif(btrim(r.name), ''), '(no name)'),
        coalesce(nullif(btrim(r.organization), ''), '(no organization)'),
        r.phone,
        r.coverage_lga,
        coalesce(r.coverage_state, 'NULL'),
        r.reason;
    end loop;
  end if;
end $$;

-- ── The constraint ──────────────────────────────────────────────────────────
--
-- No sentinel, no generated column: coverage_lga is always one concrete LGA,
-- so both halves of the key are always present and a plain composite foreign
-- key checks the pair.

alter table public.authorities alter column coverage_state set not null;

-- The state must be a real state...
alter table public.authorities add constraint authorities_coverage_state_fkey
  foreign key (coverage_state) references public.nigeria_states (name);

-- ...and the LGA must be one of that state's. (No ON UPDATE action, for the
-- same reason as alerts_target_lga_fkey: renaming canonical reference data
-- should be a deliberate migration that updates the contacts too, not a
-- silent cascade that re-points an emergency desk at another place.)
alter table public.authorities add constraint authorities_coverage_lga_fkey
  foreign key (coverage_state, coverage_lga)
  references public.nigeria_lgas (state, lga);

comment on column public.authorities.coverage_state is
  'State of the LGA this contact covers, spelled as in public.nigeria_states. Required since 20260927090000: an LGA name alone can mean two states (Bassa is in Kogi and Plateau), and a contact must never be texted about the wrong one.';
comment on column public.authorities.coverage_lga is
  'LGA this contact covers, spelled as in public.nigeria_lgas and matched for equality against reports.lga. There is no ''All'' sentinel: one row covers exactly one (coverage_state, coverage_lga).';
