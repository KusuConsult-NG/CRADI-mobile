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
returns int language sql stable security definer set search_path = public as $$
  select coalesce((select (value #>> '{}')::int from app_settings where key = p_key), p_default)
$$;

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
       or new.id is distinct from old.id then
      raise exception 'Only an admin can change role, approval, disabled status or email'
        using errcode = '42501';
    end if;
    -- is_verified may only be raised once Supabase Auth has confirmed the user.
    if new.is_verified and not old.is_verified and not exists (
         select 1 from auth.users u
          where u.id = new.id
            and (u.email_confirmed_at is not null or u.phone_confirmed_at is not null)) then
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
    coalesce(new.phone, meta ->> 'phone', ''),
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
         phone = case when new.phone is not null and new.phone <> '' then new.phone else phone end,
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
begin
  if auth.uid() is not null and pg_trigger_depth() = 1 and not public.is_staff() then
    if new.status is distinct from old.status
       or new.verification_count is distinct from old.verification_count
       or new.escalated is distinct from old.escalated
       or new.escalation_status is distinct from old.escalation_status
       or new.user_id is distinct from old.user_id
       or new.verified_at is distinct from old.verified_at
       or new.approved_at is distinct from old.approved_at
       or new.rejected_at is distinct from old.rejected_at then
      raise exception 'Only staff can change a report''s workflow state' using errcode = '42501';
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

alter table public.verifications enable row level security;

create policy verifications_select on public.verifications for select to authenticated
  using (verifier_id = auth.uid() or public.is_verifier() or public.app_role() = 'techSupport');

create policy verifications_insert on public.verifications for insert to authenticated
  with check (
    verifier_id = auth.uid()
    and public.is_verifier()
    and public.report_owner(report_id) is distinct from auth.uid()
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
