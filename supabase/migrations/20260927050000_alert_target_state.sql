-- LGA names repeat across states (Obi is in Benue and in Nasarawa), so an
-- alert's target_lga alone cannot say which Obi is meant. Alerts now also
-- record the state they target:
--
--   target_state NULL  legacy / any state: target_lga matched by name only
--                      ('All' = everyone)
--   target_state S     target_lga in S only; target_lga 'All' = every LGA of S
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

comment on column public.alerts.target_state is
  'State the alert targets (with target_lga, or every LGA of the state when target_lga = ''All''). NULL = legacy: target_lga matched in any state.';
