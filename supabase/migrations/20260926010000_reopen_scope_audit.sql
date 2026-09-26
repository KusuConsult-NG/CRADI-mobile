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
