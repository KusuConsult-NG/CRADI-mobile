# Authority contacts (SMS on approval)

When staff approve a hazard report, the Railway backend texts every authority
whose **coverage LGA** matches the report's LGA (see `backend/README.md`,
"Authority SMS").

These recipients live in the Supabase table `public.authorities` and are
managed by admins in the web admin panel: **Dashboard → Authorities**
(`CRADI-Mobile-Admin/app/dashboard/authorities`). The page:

- picks the coverage LGA from the fixed list, so it matches `reports.lga`
  exactly (the backend compares with equality);
- normalises phone numbers to `+234XXXXXXXXXX`;
- lists LGAs with **no** recipients, where an approval would text nobody.

Limits come from the admin **Settings** page: `max_sms_per_alert_event` and
`max_sms_per_lga_per_day`. An SMS provider (Termii or Twilio) must be
configured on the backend (`SMS_PROVIDER` and its credentials).

The old hard-coded `lib/core/data/authority_contacts_data.dart` (placeholder
numbers, never used) has been removed.
