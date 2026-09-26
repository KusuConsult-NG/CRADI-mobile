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
