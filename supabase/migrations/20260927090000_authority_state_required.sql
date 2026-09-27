-- Every SMS authority must name the state of the LGA it covers.
--
-- 20260927030000 added authorities.coverage_state but left it nullable, and
-- backend/src/repo.js findAuthorities() matched
--
--   coverage_lga = report.lga and (coverage_state = report.state or coverage_state is null)
--
-- so a contact whose coverage_state was never filled in was texted for its LGA
-- name in EVERY state. 6 of the 770 LGA names are not unique, so for those a
-- single contact silently covered two different places:
--
--   Bassa      Kogi, Plateau      Nasarawa   Kano, Nasarawa
--   Ifelodun   Kwara, Osun        Obi        Benue, Nasarawa
--   Irepodun   Kwara, Osun        Surulere   Lagos, Oyo
--
-- A contact for "Bassa" with no state was texted about incidents in Kogi AND
-- in Plateau — two places ~500 km apart. From here on the database rejects
-- that shape outright: coverage_state is NOT NULL, and (coverage_state,
-- coverage_lga) must be a real pair in public.nigeria_lgas.
--
-- This is the same treatment 20260927080000 gave alerts.target_state, using
-- the two reference tables that migration created (public.nigeria_states,
-- public.nigeria_lgas, seeded from lib/core/data/nigeria_locations_data.dart
-- and client-read-only). It is simpler here because authorities has NO 'All'
-- sentinel: coverage_lga is always one concrete LGA. The admin panel
-- (CRADI-Mobile-Admin app/dashboard/authorities/page.tsx) only ever offers
-- LGAs from the fixed per-state list, the backend only ever compares it for
-- equality with reports.lga, and the import tool
-- (migration/firebase-to-supabase/src/transform.js transformAuthority) only
-- ever writes a concrete LGA — so no generated "canonical" column and no
-- partial-key foreign key are needed; a plain composite FK does the job.
--
-- On a database where public.authorities is empty every step below is a
-- no-op: the UPDATEs match nothing, the quarantine table stays empty, no
-- WARNING is raised, and only the NOT NULL / foreign keys at the end take
-- effect.

-- ── Pre-existing authorities ────────────────────────────────────────────────
--
-- The rule, in order. Nothing here ever widens a contact's coverage: it is
-- only ever canonicalised, narrowed to the one state it can mean, or the row
-- is set aside. Nothing is silently dropped.
--
--   1. A coverage_state that is a known state under a different casing or
--      with padding is canonicalised ('  benue ' -> 'Benue').
--   2. A (state, LGA) pair that matches a real pair case-insensitively is
--      rewritten to the canonical spelling of both (' obi ' in 'BENUE' ->
--      'Obi' in 'Benue').
--   3. A contact with no state whose LGA name belongs to exactly one state
--      adopts that state. This is the only safe inference: 764 of the 770
--      names identify one place, so the contact already covered exactly that
--      place and nothing changes about who it is texted for.
--   4. Anything still unresolvable — an ambiguous LGA name with no state, an
--      LGA that is in no state at all, an unknown state, an LGA that is not
--      in the state the row claims — is COPIED VERBATIM into
--      public.authorities_unresolved_coverage with a per-row reason, DELETED
--      from public.authorities, and named in a WARNING.
--
--      Deleting is the only non-widening option left: the row cannot stay
--      (it cannot satisfy the constraint), and every alternative is worse —
--      picking one of the candidate states would text the wrong emergency
--      desk about incidents in a state it does not serve, and there is no
--      "all states" value to fall back to. The contact is kept in full, phone
--      number included, so an operator can put it back with the right state.

create table public.authorities_unresolved_coverage (
  id             uuid primary key,
  name           text not null default '',
  organization   text,
  phone          text not null,
  coverage_lga   text not null,
  coverage_state text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  reason         text not null,
  quarantined_at timestamptz not null default now()
);

-- NOT a client table, and NOT a place to leave data lying around.
--
-- Unlike alerts (public broadcasts), authorities rows are real operational
-- contact details — the names and mobile numbers of emergency desks and
-- officers. This table holds the ones this migration had to remove because
-- their coverage could not be resolved to one (state, LGA). It is readable
-- only by the service role (the dashboard SQL editor); anon and authenticated
-- have no grants at all, and RLS is on with no policy, so even a leaked
-- client key cannot read a single row.
--
-- RECOVERY PROCEDURE — do this as soon as the migration warns, because every
-- row here is an emergency contact that is NO LONGER BEING TEXTED:
--
--   1. List what was set aside (SQL editor, service role):
--
--        select id, name, organization, phone, coverage_lga, coverage_state, reason
--          from public.authorities_unresolved_coverage
--         order by quarantined_at;
--
--   2. For each row, decide which state that contact actually serves — ask
--      the desk if you have to. Never guess: texting the wrong state's desk
--      is the failure this migration exists to prevent.
--
--   3. Re-add it in the admin panel (Admin -> Authorities -> Add Authority),
--      choosing the LGA under its state, or insert it directly:
--
--        insert into public.authorities (name, organization, phone, coverage_lga, coverage_state)
--        values ('Bassa Emergency Desk', 'SEMA Plateau', '+2348031234567', 'Bassa', 'Plateau');
--
--   4. Delete the row from this table once it has been re-added. When the
--      table is empty it can be dropped in a later migration. Do not leave
--      personal phone numbers in a table nothing reads.
alter table public.authorities_unresolved_coverage enable row level security;
revoke all on public.authorities_unresolved_coverage from anon, authenticated;

comment on table public.authorities_unresolved_coverage is
  'SMS contacts removed by 20260927090000 because their coverage could not be resolved to one (state, LGA). Holds real names and phone numbers, verbatim, so an operator can re-add each one with the right state and then delete it from here. Service role only; see the migration for the recovery procedure. Rows here are NOT being texted.';

-- 1. Canonicalise the state spelling.
update public.authorities a
   set coverage_state = s.name
  from public.nigeria_states s
 where a.coverage_state is not null
   and lower(btrim(a.coverage_state)) = lower(s.name)
   and a.coverage_state <> s.name;

-- 2. Canonicalise a (state, LGA) pair that is real apart from case/padding.
update public.authorities a
   set coverage_state = l.state,
       coverage_lga   = l.lga
  from public.nigeria_lgas l
 where a.coverage_state is not null
   and lower(btrim(a.coverage_state)) = lower(l.state)
   and lower(btrim(a.coverage_lga)) = lower(l.lga)
   and (a.coverage_state, a.coverage_lga) is distinct from (l.state, l.lga);

-- 3. An LGA name that belongs to exactly one state fixes its own state.
update public.authorities a
   set coverage_state = u.state,
       coverage_lga   = u.lga
  from (
    select lower(lga) as key, min(state) as state, min(lga) as lga
      from public.nigeria_lgas
     group by lower(lga)
    having count(*) = 1
  ) u
 where a.coverage_state is null
   and lower(btrim(a.coverage_lga)) = u.key;

-- 4. Set aside whatever is left, loudly.
with unresolved as (
  select a.*,
         case
           when a.coverage_state is not null
             and not exists (select 1 from public.nigeria_states s where s.name = a.coverage_state)
             then format('coverage_state %L is not a Nigerian state', a.coverage_state)
           when a.coverage_state is null and exists (
                  select 1 from public.nigeria_lgas l where lower(l.lga) = lower(btrim(a.coverage_lga)))
             then format('coverage_lga %L is an LGA of more than one state (%s) and the contact names none',
                         a.coverage_lga,
                         (select string_agg(l.state, ', ' order by l.state)
                            from public.nigeria_lgas l where lower(l.lga) = lower(btrim(a.coverage_lga))))
           when a.coverage_state is null
             then format('coverage_lga %L is not an LGA of any state and the contact names no state', a.coverage_lga)
           else format('%L is not an LGA of %L', a.coverage_lga, a.coverage_state)
         end as reason
    from public.authorities a
   where a.coverage_state is null
      or not exists (select 1 from public.nigeria_states s where s.name = a.coverage_state)
      or not exists (select 1 from public.nigeria_lgas l
                      where l.state = a.coverage_state and l.lga = btrim(a.coverage_lga))
)
insert into public.authorities_unresolved_coverage
  (id, name, organization, phone, coverage_lga, coverage_state, created_at, updated_at, reason)
select id, name, organization, phone, coverage_lga, coverage_state, created_at, updated_at, reason
  from unresolved;

delete from public.authorities a
 using public.authorities_unresolved_coverage q
 where q.id = a.id;

do $$
declare
  n bigint;
  r record;
begin
  select count(*) into n from public.authorities_unresolved_coverage;
  if n > 0 then
    raise warning 'authority_state_required: % SMS contact(s) cover an LGA that cannot be resolved to one state. They were copied to public.authorities_unresolved_coverage and removed from public.authorities, and are NO LONGER BEING TEXTED. Re-add each one with the right state (admin panel -> Authorities), then delete it from that table:', n;
    for r in select id, name, organization, phone, coverage_lga, coverage_state, reason
               from public.authorities_unresolved_coverage order by created_at loop
      raise warning '  authority % (% / %, phone %): covers % in % -- %',
        r.id,
        coalesce(nullif(btrim(r.name), ''), '(no name)'),
        coalesce(nullif(btrim(r.organization), ''), '(no organization)'),
        r.phone,
        r.coverage_lga,
        coalesce(r.coverage_state, 'NULL'),
        r.reason;
    end loop;
  end if;
end $$;

-- ── The constraint ──────────────────────────────────────────────────────────
--
-- No sentinel, no generated column: coverage_lga is always one concrete LGA,
-- so both halves of the key are always present and a plain composite foreign
-- key checks the pair.

alter table public.authorities alter column coverage_state set not null;

-- The state must be a real state...
alter table public.authorities add constraint authorities_coverage_state_fkey
  foreign key (coverage_state) references public.nigeria_states (name);

-- ...and the LGA must be one of that state's. (No ON UPDATE action, for the
-- same reason as alerts_target_lga_fkey: renaming canonical reference data
-- should be a deliberate migration that updates the contacts too, not a
-- silent cascade that re-points an emergency desk at another place.)
alter table public.authorities add constraint authorities_coverage_lga_fkey
  foreign key (coverage_state, coverage_lga)
  references public.nigeria_lgas (state, lga);

comment on column public.authorities.coverage_state is
  'State of the LGA this contact covers, spelled as in public.nigeria_states. Required since 20260927090000: an LGA name alone can mean two states (Bassa is in Kogi and Plateau), and a contact must never be texted about the wrong one.';
comment on column public.authorities.coverage_lga is
  'LGA this contact covers, spelled as in public.nigeria_lgas and matched for equality against reports.lga. There is no ''All'' sentinel: one row covers exactly one (coverage_state, coverage_lga).';
