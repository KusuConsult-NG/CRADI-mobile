# Authority contacts (SMS on approval)

When staff approve a hazard report, the Railway backend texts every authority
whose **coverage state and LGA** match the report's (see `backend/README.md`,
"Authority SMS").

A contact covers exactly one `(coverage_state, coverage_lga)` — the state is
required. Six of the 770 LGA names belong to two states each:

| LGA | States | | LGA | States |
| --- | --- | --- | --- | --- |
| Bassa | Kogi, Plateau | | Nasarawa | Kano, Nasarawa |
| Ifelodun | Kwara, Osun | | Obi | Benue, Nasarawa |
| Irepodun | Kwara, Osun | | Surulere | Lagos, Oyo |

so an LGA name on its own does not say where a contact is, and a contact for
Obi in Benue must never be texted about Obi in Nasarawa. Migration
`20260927090000` makes that impossible: `authorities.coverage_state` is NOT
NULL and `(coverage_state, coverage_lga)` is a foreign key into
`public.nigeria_lgas`, so a contact without a state, with an invented state, or
with an LGA that is not in the state it claims, is rejected by the database.
Contacts that predate the rule and could not be resolved were set aside in
`public.authorities_unresolved_coverage`; see `DEPLOYMENT-SUPABASE.md` →
*Authority SMS do not arrive* for how to get them back into service.

A report whose own `state` is empty matches no contact and sends no SMS
(logged as `sms.report_without_state`). Fix the report, not the query.

These recipients live in the Supabase table `public.authorities` and are
managed by admins in the web admin panel: **Dashboard → Authorities**
(`CRADI-Mobile-Admin/app/dashboard/authorities`). The page:

- picks the state and LGA together from the fixed list (options are grouped
  under their state), so both match `reports.state` / `reports.lga` exactly —
  the backend compares with equality — and an LGA can never be submitted
  without its state;
- normalises phone numbers to `+234XXXXXXXXXX`;
- refuses the same number twice for one `(state, LGA)`, while still allowing it
  to cover a same-named LGA in another state;
- lists **(state, LGA)** pairs with no recipients, where an approval would text
  nobody — Obi, Benue and Obi, Nasarawa are counted separately.

Limits come from the admin **Settings** page: `max_sms_per_alert_event` and
`max_sms_per_lga_per_day`. An SMS provider (Termii or Twilio) must be
configured on the backend (`SMS_PROVIDER` and its credentials).

The old hard-coded `lib/core/data/authority_contacts_data.dart` (placeholder
numbers, never used) has been removed.
