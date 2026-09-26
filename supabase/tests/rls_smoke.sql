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
