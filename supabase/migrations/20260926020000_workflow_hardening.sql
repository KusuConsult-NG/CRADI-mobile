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
