-- Every hazard category through the DB workflow: insert -> 2 peer confirmations
-- -> verified -> staff approval, and the outbox events it queues. Run after
-- local_stubs.sql + migrations on a fresh database (see README).
\set ON_ERROR_STOP 1
create or replace function as_user(u text) returns void language sql as $$ select set_config('request.jwt.claim.sub', u, false) $$;
insert into auth.users values
 ('00000000-0000-0000-0000-0000000000a1','rep@x.com',null,'{"name":"Reporter","ward":"W1","lga":"Makurdi","state":"Benue"}',now(),null),
 ('00000000-0000-0000-0000-0000000000a2','m1@x.com',null,'{"name":"M1","role":"ewm","ward":"W1","lga":"Makurdi","state":"Benue"}',now(),null),
 ('00000000-0000-0000-0000-0000000000a3','m2@x.com',null,'{"name":"M2","role":"ewm","ward":"W1","lga":"Makurdi","state":"Benue"}',now(),null),
 ('00000000-0000-0000-0000-0000000000a4','v1@x.com',null,'{"name":"V1","role":"ewv","ward":"W9","lga":"Makurdi","state":"Benue"}',now(),null);
update profiles set is_approved=true where role<>'user';
create temp table results(category text, stored text, after_insert text, after_votes text, votes int, after_approve text, events text);
grant all on results to authenticated;
do $$
declare
  cats text[] := array['Flooding','Extreme Temperatures','Drought','Windstorms','Wildfires','Erosion','Pest Outbreak','Crop Disease','Conflict'];
  c text; rid uuid; s1 text; s2 text; s3 text; n int; ev text;
begin
  foreach c in array cats loop
    rid := gen_random_uuid();
    perform as_user('00000000-0000-0000-0000-0000000000a1'); set local role authenticated;
    insert into reports(id,user_id,hazard_type,severity,lga,ward,state,description)
      values (rid, auth.uid(), c, 'high', 'Makurdi','W1','Benue','test '||c);
    select status into s1 from reports where id=rid;
    perform as_user('00000000-0000-0000-0000-0000000000a2');
    insert into verifications(report_id,is_confirmed,comment) values (rid,true,'');
    perform as_user('00000000-0000-0000-0000-0000000000a3');
    insert into verifications(report_id,is_confirmed,comment) values (rid,true,'');
    select status, verification_count into s2, n from reports where id=rid;
    perform as_user('00000000-0000-0000-0000-0000000000a4');
    update reports set status='approved' where id=rid;
    select status into s3 from reports where id=rid;
    reset role;
    select string_agg(event_type || coalesce(':'||(payload->>'new_status'),''), ', ' order by id) into ev
      from notification_outbox where payload->>'report_id' = rid::text;
    insert into results values (c, (select hazard_type from reports where id=rid), s1, s2, n, s3, ev);
  end loop;
end $$;
select * from results;
