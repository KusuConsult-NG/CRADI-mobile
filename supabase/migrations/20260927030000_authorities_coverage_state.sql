-- LGA names repeat across states (e.g. Obi in Benue and in Nasarawa), so SMS
-- recipients also record the state they cover. Rows with coverage_state NULL
-- (legacy) still match by LGA name only; the admin panel sets it for new and
-- edited rows, and the backend matches (lga, state).

alter table public.authorities add column coverage_state text;

create index authorities_lga_state_idx on public.authorities (coverage_lga, coverage_state);
