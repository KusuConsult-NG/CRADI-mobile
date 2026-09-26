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
