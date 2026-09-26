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
