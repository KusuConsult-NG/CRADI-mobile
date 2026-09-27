-- LGA names repeat across states (e.g. Obi in Benue and in Nasarawa), so SMS
-- recipients also record the state they cover. The admin panel sets it for new
-- and edited rows, and the backend matches (lga, state).
--
-- SUPERSEDED by 20260927090000: this migration left coverage_state nullable,
-- and a row with NULL was matched by LGA name alone — so a contact for one of
-- the 6 ambiguous names (Bassa, Ifelodun, Irepodun, Nasarawa, Obi, Surulere)
-- was texted about incidents in both of its states. 20260927090000 resolves or
-- quarantines those rows and makes the column NOT NULL with foreign keys into
-- public.nigeria_states / public.nigeria_lgas. Nothing nullable survives.

alter table public.authorities add column coverage_state text;

create index authorities_lga_state_idx on public.authorities (coverage_lga, coverage_state);
