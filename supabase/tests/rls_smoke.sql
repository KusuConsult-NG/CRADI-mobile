\set ON_ERROR_STOP 0
-- users: reporter (asks admin), two ewms, an admin, a stranger
insert into auth.users values
 ('00000000-0000-0000-0000-00000000000a','rep@x.com',null,'{"name":"Rep","role":"admin","ward":"W1","lga":"L1"}',now(),null),
 ('00000000-0000-0000-0000-00000000000b','e1@x.com',null,'{"name":"E1","role":"ewm","ward":"W1","lga":"L1"}',now(),null),
 ('00000000-0000-0000-0000-00000000000c','e2@x.com',null,'{"name":"E2","role":"ewm","ward":"W1","lga":"L1"}',now(),null),
 ('00000000-0000-0000-0000-00000000000d','ad@x.com',null,'{"name":"Ad"}',now(),null),
 ('00000000-0000-0000-0000-00000000000e','st@x.com',null,'{"name":"St"}',null,null);
update profiles set role='admin', is_approved=true where email='ad@x.com'; -- bootstrap (no auth.uid → allowed)
select email, role, is_approved, is_verified from profiles order by email;

create function as_user(u text) returns void language sql as $$ select set_config('request.jwt.claim.sub', u, false) $$;

\echo '--- 1 reporter tries to self-promote (expect ERROR)'
set role authenticated; select as_user('00000000-0000-0000-0000-00000000000a');
update profiles set role='admin' where id=auth.uid();
update profiles set is_approved=true where id=auth.uid();
\echo '--- stranger (unconfirmed) tries to set is_verified (expect ERROR)'
select as_user('00000000-0000-0000-0000-00000000000e');
update profiles set is_verified=true where id=auth.uid();
\echo '--- stranger can edit own name (expect UPDATE 1)'
update profiles set name='Stranger' where id=auth.uid();

\echo '--- 2 reporter inserts verified report (expect ERROR) then pending (ok)'
select as_user('00000000-0000-0000-0000-00000000000a');
insert into reports(id,user_id,hazard_type,lga,ward,status) values ('10000000-0000-0000-0000-000000000001',auth.uid(),'Flood','L1','W1','verified');
insert into reports(id,user_id,hazard_type,lga,ward,severity) values ('10000000-0000-0000-0000-000000000001',auth.uid(),'Flood','L1','W1','high');
\echo '--- owner tries to mark verified (expect ERROR)'
update reports set status='verified' where id='10000000-0000-0000-0000-000000000001';
\echo '--- owner edits description (expect UPDATE 1)'
update reports set description='water rising' where id='10000000-0000-0000-0000-000000000001';

\echo '--- 3 unapproved ewm cannot see or verify (expect 0 rows, ERROR)'
select as_user('00000000-0000-0000-0000-00000000000b');
select count(*) from reports;
insert into verifications(report_id,is_confirmed) values ('10000000-0000-0000-0000-000000000001',true);

\echo '--- 4 admin approves ewms'
select as_user('00000000-0000-0000-0000-00000000000d');
update profiles set is_approved=true where role='ewm';

\echo '--- 5 ewms verify; reporter cannot verify own'
select as_user('00000000-0000-0000-0000-00000000000b');
select count(*) as ewm_sees from reports;
insert into verifications(report_id,is_confirmed) values ('10000000-0000-0000-0000-000000000001',true);
insert into verifications(report_id,is_confirmed) values ('10000000-0000-0000-0000-000000000001',true);
select as_user('00000000-0000-0000-0000-00000000000c');
insert into verifications(report_id,is_confirmed) values ('10000000-0000-0000-0000-000000000001',true);
reset role;
select status, verification_count, is_alert, reporter_name, escalation_status from reports;
select status, reason from scheduled_escalations;
select event_type, payload->>'new_status' ns from notification_outbox order by id;

\echo '--- 6 contacts isolation'
set role authenticated; select as_user('00000000-0000-0000-0000-00000000000a');
insert into contacts(name,phone) values ('Mum','123');
select as_user('00000000-0000-0000-0000-00000000000e');
select count(*) as stranger_sees_contacts from contacts;
insert into contacts(user_id,name,phone) values ('00000000-0000-0000-0000-00000000000a','x','1');
\echo '--- stranger reads other profiles (expect 1 = own only)'
select count(*) from profiles;
\echo '--- anon cannot read reports'
set role anon; select count(*) from reports;
reset role;
\echo '--- outbox claim'
select event_type, attempts from claim_outbox_events(10);

\echo '=== round 2: workflow permissions ==='
insert into auth.users values
 ('00000000-0000-0000-0000-00000000000f','ewv@x.com',null,'{"name":"V","role":"ewv","ward":"W9","lga":"L1"}',now(),null),
 ('00000000-0000-0000-0000-000000000010','e3@x.com','2348000000001','{"name":"E3","role":"ewm","ward":"W2","lga":"L1"}',now(),null);
select set_config('request.jwt.claim.sub','',false);
update profiles set is_approved=true where email in ('ewv@x.com','e3@x.com');
select phone as phone_gets_plus from profiles where email='e3@x.com';
set role authenticated;
select as_user('00000000-0000-0000-0000-00000000000a');
insert into reports(id,user_id,hazard_type,lga,ward) values ('10000000-0000-0000-0000-000000000002',auth.uid(),'Fire','L1','W1');
\echo '--- ewm sets approved (expect ERROR)'
select as_user('00000000-0000-0000-0000-00000000000b');
update reports set status='approved' where id='10000000-0000-0000-0000-000000000002';
\echo '--- ewm sets verified directly (expect ERROR)'
update reports set status='verified' where id='10000000-0000-0000-0000-000000000002';
\echo '--- ewm from other ward verifies (expect ERROR)'
select as_user('00000000-0000-0000-0000-000000000010');
insert into verifications(report_id,is_confirmed) values ('10000000-0000-0000-0000-000000000002',true);
\echo '--- approved ewm moves ward (expect ERROR)'
update profiles set ward='W1' where id=auth.uid();
\echo '--- ewv approves someone else''s report (expect UPDATE 1)'
select as_user('00000000-0000-0000-0000-00000000000f');
update reports set status='approved', approved_at=now() where id='10000000-0000-0000-0000-000000000002';
\echo '--- ewv tries to approve own report (expect ERROR)'
reset role;
insert into reports(id,user_id,hazard_type,lga,ward) values ('10000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-00000000000f','Fire','L1','W9');
set role authenticated; select as_user('00000000-0000-0000-0000-00000000000f');
update reports set status='approved' where id='10000000-0000-0000-0000-000000000003';
\echo '--- confirmed user sets is_verified (expect UPDATE 1, no permission error)'
select as_user('00000000-0000-0000-0000-00000000000b');
update profiles set is_verified=true where id=auth.uid();
\echo '--- anon cannot call report_owner (expect ERROR)'
reset role; set role anon;
select public.report_owner('10000000-0000-0000-0000-000000000002');
reset role;
\echo '--- bad setting does not break inserts (expect INSERT ok)'
update app_settings set value='"abc"' where key='escalation_timeout_minutes';
insert into reports(user_id,hazard_type,lga) values ('00000000-0000-0000-0000-00000000000a','Flood','L1');
select count(*) as reports_total from reports;

\echo '=== round 3: disputes ==='
select set_config('request.jwt.claim.sub','',false);
insert into reports(id,user_id,hazard_type,lga,ward) values ('10000000-0000-0000-0000-000000000004','00000000-0000-0000-0000-00000000000a','Storm','L1','W1');
set role authenticated; select as_user('00000000-0000-0000-0000-00000000000b');
insert into verifications(report_id,is_confirmed,comment) values ('10000000-0000-0000-0000-000000000004',false,'not true');
reset role;
select event_type from notification_outbox where payload->>'report_id'='10000000-0000-0000-0000-000000000004' order by id;

\echo '=== round 4: reopen, lga scoping, audit ==='
select set_config('request.jwt.claim.sub','',false);
insert into auth.users values ('00000000-0000-0000-0000-000000000011','e4@x.com',null,'{"name":"E4","role":"ewm","ward":"W1","lga":"L2"}',now(),null);
update profiles set is_approved=true where email='e4@x.com';
set role authenticated;
\echo '--- ewm with same ward name in another LGA sees 0 of L1 reports'
select as_user('00000000-0000-0000-0000-000000000011');
select count(*) as other_lga_sees from reports where lga='L1';
\echo '--- ewm cannot reopen (expect ERROR)'
select reopen_report('10000000-0000-0000-0000-000000000001');
\echo '--- ewv reopens verified report 1 (expect ok) and it can be re-verified'
select as_user('00000000-0000-0000-0000-00000000000f');
select reopen_report('10000000-0000-0000-0000-000000000001');
reset role;
select status, verification_count, escalated from reports where id='10000000-0000-0000-0000-000000000001';
select count(*) as votes_left from verifications where report_id='10000000-0000-0000-0000-000000000001';
select count(*) as pending_escalations from scheduled_escalations where report_id='10000000-0000-0000-0000-000000000001' and status='pending';
\echo '--- approval was audited'
select action from verification_overrides where report_id='10000000-0000-0000-0000-000000000002';

\echo '=== round 5: workflow hardening ==='
set role authenticated; select as_user('00000000-0000-0000-0000-00000000000f');
\echo '--- ewv plain status->pending on approved report 2 (expect ERROR use reopen_report)'
update reports set status='pending' where id='10000000-0000-0000-0000-000000000002';
\echo '--- reopen an already pending report 1 (expect ERROR already pending)'
select reopen_report('10000000-0000-0000-0000-000000000001');
\echo '--- ewm votes on approved report 2 (expect ERROR rls)'
select as_user('00000000-0000-0000-0000-00000000000c');
insert into verifications(report_id,is_confirmed) values ('10000000-0000-0000-0000-000000000002',true);
\echo '--- ewm edits another user''s report description (expect ERROR only the reporter)'
update reports set description='changed' where id='10000000-0000-0000-0000-000000000001';
\echo '--- ewv rejects report 2 with reason; approved_at cleared'
select as_user('00000000-0000-0000-0000-00000000000f');
update reports set status='rejected', rejection_reason='duplicate' where id='10000000-0000-0000-0000-000000000002';
reset role;
select status, approved_at is null as approved_cleared, rejected_at is not null as rejected_set from reports where id='10000000-0000-0000-0000-000000000002';
\echo '--- audit rows survive deleting the validator'
delete from auth.users where id='00000000-0000-0000-0000-00000000000f';
select action, validator_id is null as validator_nulled from verification_overrides where report_id='10000000-0000-0000-0000-000000000002' order by created_at;

\echo '=== round 6: security hardening ==='
select set_config('request.jwt.claim.sub','',false);
insert into auth.users values ('00000000-0000-0000-0000-000000000012','new@x.com',null,'{"name":"Newbie"}',now(),null);
set role authenticated;
\echo '--- unapproved user cannot read or post chat (expect 0 rows, ERROR rls)'
select as_user('00000000-0000-0000-0000-000000000012');
select count(*) as chat_visible from messages;
insert into messages(message) values ('hi');
\echo '--- approved ewm posts chat with spoofed sender_name (stored as real name)'
select as_user('00000000-0000-0000-0000-00000000000b');
insert into messages(message, sender_name) values ('hello', 'CRADI Admin');
select sender_name from messages order by created_at desc limit 1;
\echo '--- spoofed reporter_name / workflow fields on insert are overwritten'
select as_user('00000000-0000-0000-0000-00000000000a');
insert into reports(id,user_id,hazard_type,lga,ward,reporter_name,approved_at) values ('10000000-0000-0000-0000-000000000009',auth.uid(),'Flood','L1','W1','Someone Else',now());
select reporter_name, approved_at is null as approved_cleared from reports where id='10000000-0000-0000-0000-000000000009';
\echo '--- over-long hazard_type (expect ERROR check)'
insert into reports(user_id,hazard_type,lga) values (auth.uid(), repeat('x',61),'L1');
\echo '--- report_owner oracle: plain user asks about someone else''s report (expect NULL)'
select as_user('00000000-0000-0000-0000-000000000012');
select report_owner('10000000-0000-0000-0000-000000000009') as leaked_owner;
\echo '--- plain user cannot see other profiles; ewm sees only same-area peers'
select count(*) as newbie_sees_profiles from profiles;
select as_user('00000000-0000-0000-0000-000000000011');
select count(*) as other_area_ewm_sees from profiles where lga='L1';
\echo '--- alert with forged author (expect ERROR rls); override insert (expect ERROR rls)'
select as_user('00000000-0000-0000-0000-00000000000d');
insert into alerts(title, created_by) values ('x','00000000-0000-0000-0000-00000000000b');
insert into verification_overrides(report_id,action) values ('10000000-0000-0000-0000-000000000009','approved');
\echo '--- staff editing another report''s reporter_name (expect ERROR only the reporter)'
select as_user('00000000-0000-0000-0000-00000000000b');
update reports set reporter_name='X' where id='10000000-0000-0000-0000-000000000009';
reset role;

\echo '=== round 7: approval needs confirmation ==='
reset role;
select set_config('request.jwt.claim.sub','',false);
insert into auth.users values ('00000000-0000-0000-0000-000000000013','unconf@x.com',null,'{"name":"Unconfirmed","role":"ewm"}',null,null);
\echo '--- approving an unconfirmed account, even as service role (expect ERROR)'
update profiles set is_approved=true where id='00000000-0000-0000-0000-000000000013';
update auth.users set email_confirmed_at=now() where id='00000000-0000-0000-0000-000000000013';
\echo '--- after confirming, approval works (expect UPDATE)'
update profiles set is_approved=true where id='00000000-0000-0000-0000-000000000013';
select is_approved from profiles where id='00000000-0000-0000-0000-000000000013';

\echo '=== round 8: blocking queues an auth-ban sync ==='
reset role;
select set_config('request.jwt.claim.sub','',false);
update profiles set is_disabled=true where id='00000000-0000-0000-0000-000000000013';
update profiles set is_disabled=false where id='00000000-0000-0000-0000-000000000013';
select count(*) as access_events from notification_outbox where event_type='user_access_changed' and payload->>'user_id'='00000000-0000-0000-0000-000000000013';
select count(*) as dead_settings from app_settings where key in ('sms_dedup_window_minutes','content_cache_ttl_hours','max_report_image_mb','feature_flag_voice_reports');

\echo '=== round 9: admin-managed built-in content ==='
reset role;
select count(*) as seeded_guides from knowledge_base where hazard_type in ('flood','erosion','extreme_heat','fire','conflict','accident','storm','earthquake','disease','safety');
select count(*) as seeded_news_links from news_links;
update news_links set is_active=false where source='UNDRR';
set role authenticated;
select as_user('00000000-0000-0000-0000-00000000000a');
\echo '--- plain user sees only active links (expect 3)'
select count(*) as visible_news_links from news_links;
\echo '--- plain user adds a link (expect ERROR rls)'
insert into news_links(title,url) values ('x','https://example.org');
\echo '--- admin adds a link with a non-http url (expect ERROR check)'
select as_user('00000000-0000-0000-0000-00000000000d');
insert into news_links(title,url) values ('x','javascript:alert(1)');
\echo '--- admin sees the inactive link too (expect 4)'
select count(*) as admin_news_links from news_links;
reset role;
