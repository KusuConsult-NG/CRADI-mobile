# Authority contacts (SMS on approval)

When staff approve a hazard report, the server texts every authority whose
**coverage state and LGA** match the report's. On the Appwrite stack that is
the `worker` Function (`functions/cradi/src/lib/termii.js`); on the Supabase
stack it is the Railway backend (`backend/README.md`, "Authority SMS"). The
rule, the caps and the receipts are the same on both — the Appwrite port was
written against the Railway implementation precisely so they would stay the
same.

A contact covers exactly one state-and-LGA pair — `coverageState` /
`coverageLga` on Appwrite, `coverage_state` / `coverage_lga` in Postgres —
and the state is required. Six of the 770 LGA names belong to two states each:

| LGA | States | | LGA | States |
| --- | --- | --- | --- | --- |
| Bassa | Kogi, Plateau | | Nasarawa | Kano, Nasarawa |
| Ifelodun | Kwara, Osun | | Obi | Benue, Nasarawa |
| Irepodun | Kwara, Osun | | Surulere | Lagos, Oyo |

so an LGA name on its own does not say where a contact is, and a contact for
Obi in Benue must never be texted about Obi in Nasarawa. Both stacks make that
impossible, in the only way each can:

- **Postgres** refuses it in the database. Migration `20260927090000` makes
  `authorities.coverage_state` NOT NULL and `(coverage_state, coverage_lga)` a
  foreign key into `public.nigeria_lgas`, so a contact without a state, with
  an invented state, or with an LGA that is not in the state it claims, is
  rejected at insert time.
- **Appwrite has neither CHECK constraints nor foreign keys**, and
  `coverageState` is not a required column, so the same rule is code:
  `assertCoverage` in `functions/cradi/src/lib/policy.js`, which every write
  to `authorities` goes through. It checks the LGA against the state's own
  list, so "Obi, Kano" is refused as firmly as a missing state.
  `cloud-check.mjs` asserts both halves against a live project, because a
  guard that moved from the database into a Function is exactly the kind that
  can be quietly lost.

Contacts that predate the Postgres rule and could not be resolved were set
aside in `authorities_unresolved_coverage`, which exists on both stacks; see
`DEPLOYMENT-SUPABASE.md` → *Authority SMS do not arrive* for how to get them
back into service.

A report whose own `state` is empty matches no contact and sends no SMS
(logged as `sms.report_without_state`). Fix the report, not the query.

These recipients live in the `authorities` collection (the Supabase table
`public.authorities` on the old stack) and are managed by admins in the web
admin panel: **Dashboard → Authorities**
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
`max_sms_per_lga_per_day`.

The provider has to be configured, or every send is skipped with a line in
the log and nothing else:

- **Appwrite:** Termii only, called directly by the `worker` Function.
  `TERMII_API_KEY` and `TERMII_SENDER_ID` are Function variables, set from
  the environment by `infra/appwrite/local/deploy.mjs` — which **replaces a
  Function's variables wholesale**, so a key typed into the console does not
  survive the next deploy. The script prints `SMS: OFF` when it deployed
  without them. There is no provider switch: Twilio was not ported, because
  Termii is what delivers in Nigeria and is the only one that was ever used.
- **Supabase:** `SMS_PROVIDER` (Termii or Twilio) and its credentials, on the
  Railway backend.

The old hard-coded `lib/core/data/authority_contacts_data.dart` (placeholder
numbers, never used) has been removed.
