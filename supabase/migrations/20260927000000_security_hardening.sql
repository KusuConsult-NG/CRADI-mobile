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
