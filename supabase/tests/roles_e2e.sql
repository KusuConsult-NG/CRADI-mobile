-- ═══════════════════════════════════════════════════════════════════════════
--  Every user role × every hazard category, at the database level.
--
--  Run on a FRESH database, after local_stubs.sql + every migration:
--
--    createdb role_e2e
--    psql -d role_e2e -f supabase/tests/local_stubs.sql
--    for f in supabase/migrations/*.sql; do psql -d role_e2e -v ON_ERROR_STOP=1 -f "$f"; done
--    psql -d role_e2e -f supabase/tests/roles_e2e.sql
--
--  A CORRECT RUN PRINTS EXACTLY 39 "ERROR:" LINES — every one of them from a
--  statement marked "(expect ERROR)" in part 2. Any other ERROR line, or a
--  missing one, is a failure.
--
--  Parts 3 and 4 never print ERROR: their refusals are caught inside
--  plpgsql and recorded, so they show up as PASS / FAIL rows instead.
--
--  The last three SELECTs must print:
--    * role capability matrix   — every cell "PASS"   (8 roles × 26 caps)
--    * hazard lifecycle matrix  — every cell "PASS"   (9 hazards × 14 steps)
--    * summary                  — failures = 0
-- ═══════════════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP 0

create function as_user(u text) returns void language sql as
  $$ select set_config('request.jwt.claim.sub', u, false) $$;

-- Runs one statement under the current authenticated identity and reports
-- 'ok' (rows changed), 'norows' (policy filtered every row away) or
-- 'ERR:<sqlstate>'. The inner block is a subtransaction, so nothing the
-- statement did survives — probes never disturb the next probe.
create function probe(sql text) returns text language plpgsql as $$
declare n int;
begin
  begin
    execute sql;
    get diagnostics n = row_count;
    raise exception 'PROBE_OK:%', n;
  exception when others then
    if sqlerrm like 'PROBE_OK:%' then
      return case when split_part(sqlerrm, ':', 2) = '0' then 'norows' else 'ok' end;
    end if;
    return 'ERR:' || sqlstate;
  end;
end $$;

create function probe_count(sql text) returns text language plpgsql as $$
declare n int;
begin
  begin
    execute sql into n;
    return n::text;
  exception when others then
    return 'ERR:' || sqlstate;
  end;
end $$;

-- Server-side state that no client role may read: notification_outbox has RLS
-- with no policy at all (backend service role only) and scheduled_escalations
-- is visible to ldp_coordinator / project_staff / admin. SECURITY DEFINER, so
-- the test can still assert on it — this is instrumentation, never a claim
-- about what a client can see.
create function sys_count(sql text) returns text language plpgsql
  security definer set search_path = public as $$
declare n int;
begin execute sql into n; return n::text; end $$;

-- ───────────────────────────── 1. users ────────────────────────────────────
-- One user per role, plus two plain reporters (near / far) and a second EWM
-- in the same ward so a report can reach the 2-confirmation threshold.
--   ward / LGA:  W1/L1 = "near"   W2/L2 = "far"   W9/L1 = staff HQ
\echo ''
\echo '=== 1. users (one per role) ==============================================='
insert into auth.users values
 ('00000000-0000-0000-0000-0000000000a1','rep1@x.com',null,'{"name":"Rep1","ward":"W1","lga":"L1","state":"S"}',now(),null),
 ('00000000-0000-0000-0000-0000000000a2','ewm1@x.com',null,'{"name":"Ewm1","role":"ewm","ward":"W1","lga":"L1","state":"S"}',now(),null),
 ('00000000-0000-0000-0000-0000000000a3','ewm2@x.com',null,'{"name":"Ewm2","role":"ewm","ward":"W1","lga":"L1","state":"S"}',now(),null),
 ('00000000-0000-0000-0000-0000000000a4','ewv@x.com',null,'{"name":"Ewv","role":"ewv","ward":"W9","lga":"L1","state":"S"}',now(),null),
 ('00000000-0000-0000-0000-0000000000a5','ewr@x.com',null,'{"name":"Ewr","role":"ewr","ward":"W9","lga":"L1","state":"S"}',now(),null),
 ('00000000-0000-0000-0000-0000000000a6','ldp@x.com',null,'{"name":"Ldp","role":"ldp_coordinator","ward":"W9","lga":"L1","state":"S"}',now(),null),
 ('00000000-0000-0000-0000-0000000000a7','ps@x.com',null,'{"name":"Ps","role":"project_staff","ward":"W9","lga":"L1","state":"S"}',now(),null),
 ('00000000-0000-0000-0000-0000000000a8','admin@x.com',null,'{"name":"Admin","ward":"W9","lga":"L1","state":"S"}',now(),null),
 ('00000000-0000-0000-0000-0000000000a9','ts@x.com',null,'{"name":"Ts","ward":"W9","lga":"L1","state":"S"}',now(),null),
 ('00000000-0000-0000-0000-0000000000b1','rep2@x.com',null,'{"name":"Rep2","ward":"W2","lga":"L2","state":"S"}',now(),null),
 ('00000000-0000-0000-0000-0000000000b2','plain@x.com',null,'{"name":"Plain","ward":"W1","lga":"L1","state":"S"}',now(),null);
-- 'admin' and 'techSupport' are not self-assignable at sign-up (handle_new_user
-- downgrades them), so they are set here the way an admin would.
update profiles set role='admin'       where email='admin@x.com';
update profiles set role='techSupport' where email='ts@x.com';
-- Every account is approved: an unapproved account is a plain 'user' to
-- app_role() and is locked out of the app by the route guard anyway.
update profiles set is_approved=true;
select role, count(*) from profiles group by role order by role;

-- ── seed rows the read probes need ──
insert into authorities(name,phone,coverage_lga,coverage_state) values ('Seed Authority','+2348000000000','Makurdi','Benue');
insert into knowledge_base(hazard_type,title,content) values ('Flooding','Seed','c');
insert into alerts(id,title,message,created_by)
  values ('30000000-0000-0000-0000-000000000001','Seed alert','m','00000000-0000-0000-0000-0000000000a8');
insert into messages(sender_id,message) values ('00000000-0000-0000-0000-0000000000a8','seed');

-- ── fixture reports ──
--  r1 near pending (rep1, W1/L1)   r2 near, driven to 'verified'
--  r3 far pending (rep2, W2/L2)    own_<role> one pending report per role
insert into reports(id,user_id,hazard_type,severity,lga,ward,state,description) values
 ('20000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','Flooding','high','L1','W1','S','near pending'),
 ('20000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-0000000000a1','Drought','high','L1','W1','S','near to verify'),
 ('20000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-0000000000b1','Wildfires','high','L2','W2','S','far pending');
insert into reports(id,user_id,hazard_type,severity,lga,ward,state,description)
  select ('21000000-0000-0000-0000-0000000000' || substr(id::text, 35, 2))::uuid,
         id, 'Conflict', 'high', 'L1', 'W1', 'S', 'own report'
    from profiles where email in
      ('ewm1@x.com','ewv@x.com','ewr@x.com','ldp@x.com','ps@x.com','admin@x.com','ts@x.com','plain@x.com');
-- The staff-owned ones are driven out of 'pending' (written with no auth.uid(),
-- so the guard stays out of the way). reopen_report() answers "already pending"
-- (22023) before it reaches the "not your own report" rule, so a pending report
-- would never test that rule. The plain user's own report stays pending, so
-- that its approve/reject refusal comes from the guard rather than from the
-- reports_update policy hiding the row.
update reports set status='rejected', rejected_at=now()
 where id::text like '21000000-%' and id <> '21000000-0000-0000-0000-0000000000b2';

-- Two same-ward EWM confirmations push r2 to 'verified' (the only way a
-- report becomes verified without an admin).
set role authenticated;
select as_user('00000000-0000-0000-0000-0000000000a2');
insert into verifications(report_id,is_confirmed,comment) values ('20000000-0000-0000-0000-000000000002',true,'');
select as_user('00000000-0000-0000-0000-0000000000a3');
insert into verifications(report_id,is_confirmed,comment) values ('20000000-0000-0000-0000-000000000002',true,'');
reset role;
\echo '--- r2 must now be verified with 2 confirmations'
select status, verification_count from reports where id='20000000-0000-0000-0000-000000000002';

-- ═════════════════ 2. explicit refusals — 39 "ERROR:" lines ═════════════════
\echo ''
\echo '=== 2. refusals (39 ERROR lines expected) ================================'
set role authenticated;

-- ── plain user (role 'user') ───────────────────────────────────────────────
\echo '--- 2.01 plain user votes on someone else''s report (expect ERROR)'
select as_user('00000000-0000-0000-0000-0000000000b2');
insert into verifications(report_id,is_confirmed,comment) values ('20000000-0000-0000-0000-000000000001',true,'');
\echo '--- 2.02 plain user disputes someone else''s report (expect ERROR)'
insert into verifications(report_id,is_confirmed,comment) values ('20000000-0000-0000-0000-000000000001',false,'nope');
\echo '--- 2.03 plain user reopens a report (expect ERROR)'
select reopen_report('20000000-0000-0000-0000-000000000002');
\echo '--- 2.04 plain user creates an alert (expect ERROR)'
insert into alerts(title,message,created_by) values ('x','y',auth.uid());
\echo '--- 2.05 plain user writes the knowledge base (expect ERROR)'
insert into knowledge_base(hazard_type,title,content) values ('Flooding','t','c');
\echo '--- 2.06 plain user writes app settings (expect ERROR)'
insert into app_settings(key,value) values ('zz','1');
\echo '--- 2.07 plain user writes news links (expect ERROR)'
insert into news_links(title,url) values ('t','http://x');
\echo '--- 2.08 plain user writes authorities (expect ERROR)'
insert into authorities(name,phone,coverage_lga,coverage_state) values ('a','+234','Makurdi','Benue');
\echo '--- 2.09 plain user marks own report verified (expect ERROR)'
update reports set status='verified' where id='21000000-0000-0000-0000-0000000000b2';
\echo '--- 2.10 plain user approves own report (expect ERROR)'
update reports set status='approved' where id='21000000-0000-0000-0000-0000000000b2';
\echo '--- plain user approve/reject of ANOTHER report: no row passes the policy'
\echo '    (expect UPDATE 0, not an error — reports_update hides it)'
update reports set status='approved' where id='20000000-0000-0000-0000-000000000002';
\echo '--- plain user sees only its own reports (expect 1)'
select count(*) as plain_user_sees from reports;
\echo '--- plain user sees no peer votes (expect 0) and no authorities (expect 0)'
select count(*) as votes_seen from verifications;
select count(*) as authorities_seen from authorities;

-- ── ewm: votes, but never decides ──────────────────────────────────────────
\echo '--- 2.11 ewm approves another report (expect ERROR)'
select as_user('00000000-0000-0000-0000-0000000000a2');
update reports set status='approved' where id='20000000-0000-0000-0000-000000000002';
\echo '--- 2.12 ewm rejects another report (expect ERROR)'
update reports set status='rejected', rejection_reason='no' where id='20000000-0000-0000-0000-000000000002';
\echo '--- 2.13 ewm reopens a report (expect ERROR)'
select reopen_report('20000000-0000-0000-0000-000000000002');
\echo '--- 2.14 ewm creates an alert (expect ERROR)'
insert into alerts(title,message,created_by) values ('x','y',auth.uid());
\echo '--- 2.15 ewm votes outside its own ward / LGA (expect ERROR)'
insert into verifications(report_id,is_confirmed,comment) values ('20000000-0000-0000-0000-000000000003',true,'');
\echo '--- 2.16 ewm votes on its own report (expect ERROR)'
insert into verifications(report_id,is_confirmed,comment) values ('21000000-0000-0000-0000-0000000000a2',true,'');
\echo '--- 2.17 ewm sets status=verified by hand (expect ERROR)'
update reports set status='verified' where id='20000000-0000-0000-0000-000000000001';
\echo '--- ewm CAN vote in its own ward (expect INSERT 0 1)'
insert into verifications(report_id,is_confirmed,comment) values ('20000000-0000-0000-0000-000000000001',true,'');
\echo '--- ewm sees only its own area (far report invisible: expect 0)'
select count(*) as ewm_sees_far from reports where id='20000000-0000-0000-0000-000000000003';

-- ── ewr (responder): full verifier + status manager + alert manager ────────
\echo '--- 2.18 ewr votes on its own report (expect ERROR)'
select as_user('00000000-0000-0000-0000-0000000000a5');
insert into verifications(report_id,is_confirmed,comment) values ('21000000-0000-0000-0000-0000000000a5',true,'');
\echo '--- 2.19 ewr approves its own report (expect ERROR)'
update reports set status='approved' where id='21000000-0000-0000-0000-0000000000a5';
\echo '--- 2.20 ewr rejects its own report (expect ERROR)'
update reports set status='rejected', rejection_reason='no' where id='21000000-0000-0000-0000-0000000000a5';
\echo '--- ewr CAN approve another user''s verified report (expect UPDATE 1)'
update reports set status='approved' where id='20000000-0000-0000-0000-000000000002';
\echo '--- 2.21 ewr reopens its own (rejected) report (expect ERROR)'
select reopen_report('21000000-0000-0000-0000-0000000000a5');
\echo '--- 2.22 ewr sets status=verified by hand (expect ERROR)'
update reports set status='verified' where id='20000000-0000-0000-0000-000000000001';
\echo '--- 2.23 ewr moves a report back to pending with a plain UPDATE (expect ERROR)'
update reports set status='pending' where id='20000000-0000-0000-0000-000000000002';
\echo '--- 2.24 ewr writes the knowledge base (expect ERROR)'
insert into knowledge_base(hazard_type,title,content) values ('Flooding','t','c');
\echo '--- 2.25 ewr writes authorities (expect ERROR)'
insert into authorities(name,phone,coverage_lga,coverage_state) values ('a','+234','Makurdi','Benue');
\echo '--- ewr CAN vote on another ward''s report (expect INSERT 0 1)'
insert into verifications(report_id,is_confirmed,comment) values ('20000000-0000-0000-0000-000000000003',true,'');
\echo '--- ewr CAN reopen another user''s report (expect the RPC to succeed)'
select reopen_report('20000000-0000-0000-0000-000000000002');
\echo '--- ewr CAN create an alert (expect INSERT 0 1)'
insert into alerts(title,message,created_by) values ('ewr alert','y',auth.uid());
\echo '--- ewr CAN send a verification request (a report row of that type)'
insert into reports(user_id,hazard_type,severity,lga,ward,state,description,type)
  values (auth.uid(),'Flooding','low','L1','W1','S','vr','verification_request');

-- ── ewv ────────────────────────────────────────────────────────────────────
\echo '--- 2.26 ewv approves its own report (expect ERROR)'
select as_user('00000000-0000-0000-0000-0000000000a4');
update reports set status='approved' where id='21000000-0000-0000-0000-0000000000a4';
\echo '--- ewv CAN reject another ward''s report (expect UPDATE 1)'
update reports set status='rejected', rejection_reason='r' where id='20000000-0000-0000-0000-000000000003';
\echo '--- 2.27 ewv reopens its own (rejected) report (expect ERROR)'
select reopen_report('21000000-0000-0000-0000-0000000000a4');

-- ── ldp_coordinator / project_staff: decide, but are not verifiers ─────────
\echo '--- 2.28 ldp_coordinator casts a peer vote (expect ERROR — not is_verifier)'
select as_user('00000000-0000-0000-0000-0000000000a6');
insert into verifications(report_id,is_confirmed,comment) values ('20000000-0000-0000-0000-000000000001',true,'');
\echo '--- 2.29 ldp_coordinator approves its own report (expect ERROR)'
update reports set status='approved' where id='21000000-0000-0000-0000-0000000000a6';
\echo '--- ldp_coordinator CAN approve another report (expect UPDATE 1)'
update reports set status='approved' where id='20000000-0000-0000-0000-000000000003';
\echo '--- ldp_coordinator CAN read peer votes (expect > 0)'
select count(*) as ldp_sees_votes from verifications;

\echo '--- 2.30 project_staff casts a peer vote (expect ERROR — not is_verifier)'
select as_user('00000000-0000-0000-0000-0000000000a7');
insert into verifications(report_id,is_confirmed,comment) values ('20000000-0000-0000-0000-000000000001',true,'');
\echo '--- 2.31 project_staff approves its own report (expect ERROR)'
update reports set status='approved' where id='21000000-0000-0000-0000-0000000000a7';
\echo '--- project_staff CAN reopen another report (expect the RPC to succeed)'
select reopen_report('20000000-0000-0000-0000-000000000003');

-- ── techSupport: is_staff() and an alert manager, but never a verifier
--    and never a decision maker. These four refusals are the boundary.
\echo '--- 2.32 techSupport casts a peer vote (expect ERROR — not is_verifier)'
select as_user('00000000-0000-0000-0000-0000000000a9');
insert into verifications(report_id,is_confirmed,comment) values ('20000000-0000-0000-0000-000000000001',true,'');
\echo '--- 2.33 techSupport approves a report (expect ERROR — not a status manager)'
update reports set status='approved' where id='20000000-0000-0000-0000-000000000002';
\echo '--- 2.34 techSupport rejects a report (expect ERROR)'
update reports set status='rejected', rejection_reason='no' where id='20000000-0000-0000-0000-000000000002';
\echo '--- 2.35 techSupport reopens a report (expect ERROR)'
select reopen_report('20000000-0000-0000-0000-000000000003');
\echo '--- 2.36 techSupport writes authorities (expect ERROR — admin only)'
insert into authorities(name,phone,coverage_lga,coverage_state) values ('a','+234','Makurdi','Benue');
\echo '--- 2.37 techSupport writes app settings (expect ERROR — admin only)'
insert into app_settings(key,value) values ('zz','1');
\echo '--- techSupport CAN create an alert, dismiss one, and edit content'
insert into alerts(title,message,created_by) values ('ts alert','y',auth.uid());
update alerts set is_active=false where id='30000000-0000-0000-0000-000000000001';
insert into knowledge_base(hazard_type,title,content) values ('Drought','ts kb','c');
insert into news_links(title,url) values ('ts news','http://x');
\echo '--- techSupport reads reports (all) and peer votes, but only its own profile'
select count(*) as ts_sees_reports from reports;
select count(*) as ts_sees_votes from verifications;
select count(*) as ts_sees_profiles from profiles;

-- ── admin ──────────────────────────────────────────────────────────────────
\echo '--- 2.38 admin votes on its own report (expect ERROR — nobody may)'
select as_user('00000000-0000-0000-0000-0000000000a8');
insert into verifications(report_id,is_confirmed,comment) values ('21000000-0000-0000-0000-0000000000a8',true,'');
\echo '--- 2.39 admin inserts an audit row by hand (expect ERROR — trigger only)'
insert into verification_overrides(report_id,validator_id,action,reason)
  values ('20000000-0000-0000-0000-000000000001',auth.uid(),'approved','');
\echo '--- admin CAN approve its own report (the only role that may)'
update reports set status='approved' where id='21000000-0000-0000-0000-0000000000a8';
\echo '--- admin CAN approve someone else''s and reopen it'
update reports set status='approved' where id='20000000-0000-0000-0000-000000000002';
select reopen_report('20000000-0000-0000-0000-000000000002');
reset role;

-- ═════════════ 3. role × capability matrix (no ERROR lines) ═════════════════
-- Every capability is probed for every role and compared with the expectation
-- derived from the policies / triggers. Refusals are caught inside plpgsql.
\echo ''
\echo '=== 3. role x capability matrix =========================================='
create table cap_matrix(role text, cap text, expected text, actual text);
grant all on cap_matrix to authenticated;

-- Fresh fixtures for part 3 (part 2 moved the old ones around).
insert into reports(id,user_id,hazard_type,severity,lga,ward,state,description) values
 ('22000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000a1','Erosion','high','L1','W1','S','p3 near pending'),
 ('22000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-0000000000a1','Windstorms','high','L1','W1','S','p3 near to decide'),
 ('22000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-0000000000b1','Wildfires','high','L2','W2','S','p3 far pending');
set role authenticated;
select as_user('00000000-0000-0000-0000-0000000000a2');
insert into verifications(report_id,is_confirmed,comment) values ('22000000-0000-0000-0000-000000000002',true,'');
select as_user('00000000-0000-0000-0000-0000000000a3');
insert into verifications(report_id,is_confirmed,comment) values ('22000000-0000-0000-0000-000000000002',true,'');
select as_user('00000000-0000-0000-0000-0000000000a8');
insert into alerts(id,title,message,created_by)
  values ('30000000-0000-0000-0000-000000000009','p3 alert','m',auth.uid());
reset role;
insert into reports(id,user_id,hazard_type,severity,lga,ward,state,description)
  select ('23000000-0000-0000-0000-0000000000' || substr(id::text, 35, 2))::uuid,
         id, 'Pest Outbreak', 'high', 'L1', 'W1', 'S', 'p3 own report'
    from profiles where email in
      ('ewm1@x.com','ewv@x.com','ewr@x.com','ldp@x.com','ps@x.com','admin@x.com','ts@x.com','plain@x.com');
-- Rejected (written with no auth.uid(), so the guard stays out of the way):
-- reopen_report() on a pending report answers 'already pending' (22023) before
-- it ever reaches the "not your own report" rule, which is what we want to test.
update reports set status='rejected', rejected_at=now()
 where id::text like '23000000-0000-0000-0000-%';

set role authenticated;
do $$
declare
  -- role, uid, then the expected result of each of the 26 capabilities.
  --   NEAR  = 22000000-…-01 pending, same ward as ewm  FAR = …-03 other ward
  --   VER   = 22000000-…-02 verified                   OWN = 23000000-…-<uid>
  probes text[] := array[
    '01 submit report',
    '02 see others'' reports (n)',
    '03 see far report (n)',
    '04 see near report (n)',
    '05 vote near',
    '06 vote far',
    '07 vote own',
    '08 dispute near',
    '09 read peer votes (n)',
    '10 request verification',
    '11 approve other',
    '12 approve own',
    '13 reject other',
    '14 reject own',
    '15 reopen other',
    '16 reopen own',
    '17 create alert',
    '18 dismiss alert',
    '19 manage users',
    '20 read profiles (n)',
    '21 knowledge base write',
    '22 authorities read (n)',
    '23 authorities write',
    '24 settings write',
    '25 news links write',
    '26 chat send'];
  -- Expectations, one row per role, in the order above.
  --   'ok' allowed · 'ERR:42501' refused by a policy/trigger
  --   'norows' the policy hides every row (a silent no-op, not an error)
  expect text[][] := array[
   -- user
   -- 12/14: the plain user's own report has left 'pending', so reports_update
   -- already hides it — the refusal is silent (0 rows), not an error.
   array['ok','0','0','0','ERR:42501','ERR:42501','ERR:42501','ERR:42501','0','ok','norows','norows','norows','norows','ERR:42501','ERR:42501','ERR:42501','norows','norows','1','ERR:42501','0','ERR:42501','ERR:42501','ERR:42501','ok'],
   -- ewm  (sees only its own ward/LGA + its own reports)
   array['ok','*','0','1','ok','ERR:42501','ERR:42501','ok','*','ok','ERR:42501','ERR:42501','ERR:42501','ERR:42501','ERR:42501','ERR:42501','ERR:42501','norows','norows','*','ERR:42501','1','ERR:42501','ERR:42501','ERR:42501','ok'],
   -- ewv
   array['ok','*','1','1','ok','ok','ERR:42501','ok','*','ok','ok','ERR:42501','ok','ERR:42501','ok','ERR:42501','ok','ok','norows','*','ERR:42501','1','ERR:42501','ERR:42501','ERR:42501','ok'],
   -- ewr  (responder: everything a verifier and a status manager may do)
   array['ok','*','1','1','ok','ok','ERR:42501','ok','*','ok','ok','ERR:42501','ok','ERR:42501','ok','ERR:42501','ok','ok','norows','*','ERR:42501','1','ERR:42501','ERR:42501','ERR:42501','ok'],
   -- ldp_coordinator  (status manager, NOT a verifier)
   array['ok','*','1','1','ERR:42501','ERR:42501','ERR:42501','ERR:42501','*','ok','ok','ERR:42501','ok','ERR:42501','ok','ERR:42501','ok','ok','norows','*','ERR:42501','1','ERR:42501','ERR:42501','ERR:42501','ok'],
   -- project_staff    (status manager, NOT a verifier)
   array['ok','*','1','1','ERR:42501','ERR:42501','ERR:42501','ERR:42501','*','ok','ok','ERR:42501','ok','ERR:42501','ok','ERR:42501','ok','ok','norows','*','ERR:42501','1','ERR:42501','ERR:42501','ERR:42501','ok'],
   -- admin            (the only role that may act on its own report)
   array['ok','*','1','1','ok','ok','ERR:42501','ok','*','ok','ok','ok','ok','ok','ok','ok','ok','ok','ok','*','ok','1','ok','ok','ok','ok'],
   -- techSupport      (is_staff + alert manager; never a verifier or decider)
   array['ok','*','1','1','ERR:42501','ERR:42501','ERR:42501','ERR:42501','*','ok','ERR:42501','ERR:42501','ERR:42501','ERR:42501','ERR:42501','ERR:42501','ok','ok','norows','1','ok','1','ERR:42501','ERR:42501','ok','ok']
  ];
  roles text[][] := array[
    array['user','00000000-0000-0000-0000-0000000000b2'],
    array['ewm','00000000-0000-0000-0000-0000000000a2'],
    array['ewv','00000000-0000-0000-0000-0000000000a4'],
    array['ewr','00000000-0000-0000-0000-0000000000a5'],
    array['ldp_coordinator','00000000-0000-0000-0000-0000000000a6'],
    array['project_staff','00000000-0000-0000-0000-0000000000a7'],
    array['admin','00000000-0000-0000-0000-0000000000a8'],
    array['techSupport','00000000-0000-0000-0000-0000000000a9']];
  i int; j int; rn text; uid text; own text; res text[];
  NEAR constant text := '22000000-0000-0000-0000-000000000001';
  VER  constant text := '22000000-0000-0000-0000-000000000002';
  FAR  constant text := '22000000-0000-0000-0000-000000000003';
begin
  for i in 1 .. array_length(roles, 1) loop
    rn := roles[i][1]; uid := roles[i][2];
    own := '23000000-0000-0000-0000-0000000000' || substr(uid, 35, 2);
    perform as_user(uid);
    res := array[
      probe(format('insert into reports(user_id,hazard_type,severity,lga,ward,state,description) values (%L,''Flooding'',''low'',''L1'',''W1'',''S'',''x'')', uid)),
      probe_count('select count(*) from reports where user_id <> auth.uid()'),
      probe_count(format('select count(*) from reports where id=%L', FAR)),
      probe_count(format('select count(*) from reports where id=%L', NEAR)),
      probe(format('insert into verifications(report_id,verifier_id,is_confirmed,comment) values (%L,%L,true,'''')', NEAR, uid)),
      probe(format('insert into verifications(report_id,verifier_id,is_confirmed,comment) values (%L,%L,true,'''')', FAR, uid)),
      probe(format('insert into verifications(report_id,verifier_id,is_confirmed,comment) values (%L,%L,true,'''')', own, uid)),
      probe(format('insert into verifications(report_id,verifier_id,is_confirmed,comment) values (%L,%L,false,''disputed'')', NEAR, uid)),
      probe_count('select count(*) from verifications'),
      probe(format('insert into reports(user_id,hazard_type,severity,lga,ward,state,description,type) values (%L,''Flooding'',''low'',''L1'',''W1'',''S'',''x'',''verification_request'')', uid)),
      probe(format('update reports set status=''approved'' where id=%L', VER)),
      probe(format('update reports set status=''approved'' where id=%L', own)),
      probe(format('update reports set status=''rejected'', rejection_reason=''no'' where id=%L', VER)),
      probe(format('update reports set status=''rejected'', rejection_reason=''no'' where id=%L', own)),
      probe(format('select reopen_report(%L)', VER)),
      probe(format('select reopen_report(%L)', own)),   -- refused for everyone but an admin
      probe(format('insert into alerts(title,message,created_by) values (''t'',''m'',%L)', uid)),
      probe('update alerts set is_active=false where id=''30000000-0000-0000-0000-000000000009'''),
      probe('update profiles set is_approved=true where email=''rep1@x.com'''),
      probe_count('select count(*) from profiles'),
      probe('insert into knowledge_base(hazard_type,title,content) values (''Flooding'',''t'',''c'')'),
      probe_count('select count(*) from authorities'),
      probe('insert into authorities(name,phone,coverage_lga,coverage_state) values (''a'',''+2341'',''Makurdi'',''Benue'')'),
      probe('insert into app_settings(key,value) values (''zz'',''1'')'),
      probe('insert into news_links(title,url) values (''t'',''http://x'')'),
      probe(format('insert into messages(sender_id,message) values (%L,''hi'')', uid))
    ];
    for j in 1 .. array_length(probes, 1) loop
      insert into cap_matrix values (rn, probes[j], expect[i][j], res[j]);
    end loop;
  end loop;
end $$;
reset role;

-- ══════════ 4. all 9 hazards through the full lifecycle (no ERROR) ══════════
-- Per hazard: submit -> refusals -> two peer confirmations -> verified ->
-- refusals -> decision -> audit -> reopen. Two hazards also walk the dispute
-- path and two the escalation path.
\echo ''
\echo '=== 4. hazard lifecycle matrix ==========================================='
create table hz_matrix(hazard text, step text, expected text, actual text);
grant all on hz_matrix to authenticated;

set role authenticated;
do $$
declare
  cats text[] := array['Flooding','Extreme Temperatures','Drought','Windstorms',
                       'Wildfires','Erosion','Pest Outbreak','Crop Disease','Conflict'];
  -- The deciding role rotates over statusManagerRoles so every one of them
  -- approves, rejects and reopens at least one hazard.
  deciders text[][] := array[
    array['ewv','00000000-0000-0000-0000-0000000000a4'],
    array['ewr','00000000-0000-0000-0000-0000000000a5'],
    array['ldp_coordinator','00000000-0000-0000-0000-0000000000a6'],
    array['project_staff','00000000-0000-0000-0000-0000000000a7'],
    array['admin','00000000-0000-0000-0000-0000000000a8']];
  REP  constant text := '00000000-0000-0000-0000-0000000000a1';  -- plain user, W1/L1
  EWM1 constant text := '00000000-0000-0000-0000-0000000000a2';
  EWR  constant text := '00000000-0000-0000-0000-0000000000a5';
  EWV  constant text := '00000000-0000-0000-0000-0000000000a4';
  TS   constant text := '00000000-0000-0000-0000-0000000000a9';
  PLAIN constant text := '00000000-0000-0000-0000-0000000000b2';
  LDP  constant text := '00000000-0000-0000-0000-0000000000a6';
  c text; i int := 0; rid uuid; dn text; du text; s text;
  procedure_note text;
begin
  foreach c in array cats loop
    i := i + 1;
    dn := deciders[((i - 1) % 5) + 1][1];
    du := deciders[((i - 1) % 5) + 1][2];
    rid := gen_random_uuid();

    -- 1. a plain user submits
    perform as_user(REP);
    insert into hz_matrix values (c, '01 user submits', 'ok',
      probe(format('insert into reports(id,user_id,hazard_type,severity,lga,ward,state,description) values (%L,%L,%L,''high'',''L1'',''W1'',''S'',''e2e'')', rid, REP, c)));
    insert into reports(id,user_id,hazard_type,severity,lga,ward,state,description)
      values (rid, REP::uuid, c, 'high', 'L1', 'W1', 'S', 'e2e');
    select status into s from reports where id = rid;
    insert into hz_matrix values (c, '02 status after insert', 'pending', s);
    -- escalation is scheduled at insert time
    insert into hz_matrix values (c, '03 escalation scheduled', '1',
      sys_count(format('select count(*) from scheduled_escalations where report_id=%L and status=''pending''', rid)));

    -- 2. who may NOT vote
    perform as_user(PLAIN);
    insert into hz_matrix values (c, '04 plain user vote refused', 'ERR:42501',
      probe(format('insert into verifications(report_id,verifier_id,is_confirmed,comment) values (%L,%L,true,'''')', rid, PLAIN)));
    perform as_user(LDP);
    insert into hz_matrix values (c, '05 ldp_coordinator vote refused', 'ERR:42501',
      probe(format('insert into verifications(report_id,verifier_id,is_confirmed,comment) values (%L,%L,true,'''')', rid, LDP)));
    perform as_user(TS);
    insert into hz_matrix values (c, '06 techSupport vote refused', 'ERR:42501',
      probe(format('insert into verifications(report_id,verifier_id,is_confirmed,comment) values (%L,%L,true,'''')', rid, TS)));
    perform as_user(REP);
    insert into hz_matrix values (c, '07 reporter vote on own refused', 'ERR:42501',
      probe(format('insert into verifications(report_id,verifier_id,is_confirmed,comment) values (%L,%L,true,'''')', rid, REP)));

    -- 3. two peers confirm: an EWM in the same ward and the responder
    perform as_user(EWM1);
    insert into verifications(report_id,is_confirmed,comment) values (rid, true, '');
    select status into s from reports where id = rid;
    insert into hz_matrix values (c, '08 after 1st vote', 'pending', s);
    perform as_user(EWR);
    insert into verifications(report_id,is_confirmed,comment) values (rid, true, '');
    select status || '/' || verification_count into s from reports where id = rid;
    insert into hz_matrix values (c, '09 ewr 2nd vote -> verified', 'verified/2', s);

    -- 4. who may NOT decide
    perform as_user(EWM1);
    insert into hz_matrix values (c, '10 ewm approve refused', 'ERR:42501',
      probe(format('update reports set status=''approved'' where id=%L', rid)));
    perform as_user(TS);
    insert into hz_matrix values (c, '11 techSupport approve refused', 'ERR:42501',
      probe(format('update reports set status=''approved'' where id=%L', rid)));

    -- 5. the rotating decider approves
    perform as_user(du);
    update reports set status = 'approved' where id = rid;
    select status into s from reports where id = rid;
    insert into hz_matrix values (c, '00 deciding role', dn, dn);
    insert into hz_matrix values (c, '12 decider approves', 'approved', s);
    insert into hz_matrix values (c, '13 decision audited', '1',
      sys_count(format('select count(*) from verification_overrides where report_id=%L and validator_id=%L and action=''approved''', rid, du)));

    -- 6. the same decider reopens: votes cleared, back to pending
    perform reopen_report(rid);
    select status || '/' || verification_count into s from reports where id = rid;
    insert into hz_matrix values (c, '14 decider reopens', 'pending/0', s);
  end loop;

  -- ── dispute path: Flooding and Crop Disease ──
  foreach c in array array['Flooding','Crop Disease'] loop
    select id into rid from reports where hazard_type = c and description = 'e2e' limit 1;
    perform as_user(EWV);
    insert into verifications(report_id,is_confirmed,comment) values (rid, false, 'looks wrong');
    insert into hz_matrix values (c, '15 dispute queues report_disputed', '1',
      sys_count(format('select count(*) from notification_outbox where event_type=''report_disputed'' and payload->>''report_id''=%L', rid::text)));
    select status into s from reports where id = rid;
    insert into hz_matrix values (c, '16 dispute does not verify', 'pending', s);
  end loop;

  -- ── escalation path: Drought and Conflict ──
  foreach c in array array['Drought','Conflict'] loop
    select id into rid from reports where hazard_type = c and description = 'e2e' limit 1;
    insert into hz_matrix values (c, '15 reopen re-armed escalation', '1',
      sys_count(format('select count(*) from scheduled_escalations where report_id=%L and status=''pending''', rid)));
    perform as_user(EWR);
    insert into hz_matrix values (c, '16 non-admin cannot self-escalate', 'ERR:42501',
      probe(format('update reports set escalated=true, escalation_status=''sent'' where id=%L', rid)));
  end loop;
  procedure_note := null;
end $$;
reset role;

-- ═══════════════════════════ 5. results ═════════════════════════════════════
\echo ''
\echo '=== 5.1 role x capability matrix (every cell must read PASS) ============='
select cap,
  max(case when role='user'            then v end) as "user",
  max(case when role='ewm'             then v end) as ewm,
  max(case when role='ewv'             then v end) as ewv,
  max(case when role='ewr'             then v end) as ewr,
  max(case when role='ldp_coordinator' then v end) as ldp,
  max(case when role='project_staff'   then v end) as pstaff,
  max(case when role='admin'           then v end) as admin,
  max(case when role='techSupport'     then v end) as techsup
from (
  select role, cap,
         case when expected = '*' or expected = actual
              then 'PASS' else 'FAIL(' || actual || '<>' || expected || ')' end as v
    from cap_matrix) t
group by cap order by cap;

\echo ''
\echo '=== 5.2 hazard lifecycle matrix (every cell must read PASS) =============='
select step,
  max(case when hazard='Flooding'             then v end) as flood,
  max(case when hazard='Extreme Temperatures' then v end) as heat,
  max(case when hazard='Drought'              then v end) as drought,
  max(case when hazard='Windstorms'           then v end) as wind,
  max(case when hazard='Wildfires'            then v end) as fire,
  max(case when hazard='Erosion'              then v end) as erosion,
  max(case when hazard='Pest Outbreak'        then v end) as pest,
  max(case when hazard='Crop Disease'         then v end) as disease,
  max(case when hazard='Conflict'             then v end) as conflict
from (
  select hazard, step,
         case when expected = actual then 'PASS'
              else 'FAIL(' || actual || '<>' || expected || ')' end as v
    from hz_matrix) t
group by step order by step;

\echo ''
\echo '=== 5.3 summary (failures must be 0) ====================================='
select 'role capabilities' as suite, count(*) as checks,
       count(*) filter (where expected <> '*' and expected is distinct from actual) as failures
  from cap_matrix
union all
select 'hazard lifecycle', count(*),
       count(*) filter (where expected is distinct from actual)
  from hz_matrix
order by 1;
