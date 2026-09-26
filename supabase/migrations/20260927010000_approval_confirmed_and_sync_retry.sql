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
