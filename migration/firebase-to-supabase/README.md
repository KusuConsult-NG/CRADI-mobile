# Firebase → Supabase data migration (CRADI / EWER)

A one-off tool that copies the live Firebase project **`ewer-8f788`** (Firebase Auth,
Firestore, Storage) into the Supabase schema in
[`supabase/migrations/20260925000000_init.sql`](../../supabase/migrations/20260925000000_init.sql).

It is a **dry run by default**. It reads Firebase and prints counts, sample transformed
rows and validation problems. It writes only when you pass `--apply`. It is
**idempotent and resumable**, so you can re-run it after a failure or to pick up
records created since the last run. Re-running does not duplicate rows.

## What gets migrated

| Firebase | Supabase | Notes |
| --- | --- | --- |
| Auth users + `users` | `auth.users` + `profiles` | Created with `auth.admin.createUser`. `profiles.legacy_firebase_uid` holds the Firebase uid |
| Storage `profile_images/{uid}/…` | bucket `profile-images` at `{newUserId}/…` | URLs in `profiles.profile_image_url` are rewritten |
| Storage `report_images/{uid}/…` | bucket `report-images` at `{newUserId}/…` | URLs in `reports.image_urls` are rewritten |
| `knowledge_base` | `knowledge_base` | upsert on `legacy_firebase_id` |
| `authorities` | `authorities` | `coverageLGA` / `lga` → `coverage_lga`, plus the `coverage_state` it needs (see below) |
| `reports` | `reports` | legacy statuses and severities are normalised. `legacy_firebase_id` holds the Firestore id |
| `alerts` | `alerts` | `targetLga` → `target_lga`, plus the `target_state` it needs (see below). A `createdBy` of `'admin'` → `null` |
| `verifications` | `verifications` | upsert on `(report_id, verifier_id)` |
| `verification_overrides` | `verification_overrides` | `timestamp` → `created_at` |
| `messages` | `messages` | ISO `sentAt` → `sent_at` |
| `contacts` | `contacts` | |
| `trusted_devices` | `trusted_devices` | upsert on `(user_id, device_fingerprint)` |
| `login_history` | `login_history` | `timestamp` → `occurred_at` |
| `ndpa_consents` | `ndpa_consents` | `uid` (or the doc id) → `user_id` |

The Supabase schema already seeds the 10 standard safety guides the app used to
bundle (migration `20260927040000_builtin_content.sql`, fixed ids, no legacy id).
Firebase `knowledge_base` documents whose title matches one of them (ignoring case,
whitespace and punctuation; `&` counts as `and`) are **skipped** and listed as
`replaced by built-in guide '…'`, so the guides are not duplicated. Any other copy (for
example one saved under a different title) is imported; review the Knowledge Base page
after importing and delete it if needed. The seeded titles live in
[`src/builtinContent.js`](src/builtinContent.js); a test parses them from the SQL file so
the list cannot drift.

The following are **not migrated**:
- `scheduled_escalations`. These are historic, and old reports must not escalate.
- `otp_verifications`, `chats` and `_ping`.
- FCM tokens (`users.fcmToken`). Push now goes through OneSignal, and devices re-register when the new app first runs.

### Normalisation rules

- **Report status:** `acknowledged → verified`, `validated → approved`, `resolved → approved`,
  `escalated → pending` with `escalated = true`. An unknown status becomes `pending` and is listed as a warning.
- **Report severity:** `'High Severity'`, `'HIGH'`, `'moderate'`, `'severe'`, `'extreme'` and similar values map to
  `low | medium | high | critical`. An unknown severity becomes `medium` and is listed as a warning.
- **Alert severity:** `info | warning | critical`. Report-style severities are mapped: high/medium → warning, low → info.
- **Roles:** matching ignores case and punctuation (`EWM`, `tech_support` …). An unknown role becomes `user`.
- **Report text limits:** the schema's check constraints are applied: `hazard_type` 1–60 characters,
  `description` ≤ 2000, `location`/`location_details`/`address` ≤ 500, `ward`/`lga`/`state` ≤ 120, at most
  10 `image_urls`. Longer values are cut (and extra images dropped) with a warning. Chat `message` text is
  cut to 2000 characters the same way.
- **Authority coverage:** `authorities.coverage_state` is mandatory (migration `20260927090000`) —
  an SMS contact covers exactly one `(coverage_state, coverage_lga)`, because LGA names repeat
  across states and a contact must never be texted about the wrong one. A state in the Firestore
  document is mapped case-insensitively to the canonical names `reports.state` holds (36 states +
  `FCT`, as in the app's `nigeria_locations_data.dart`): `Benue State` → `Benue`, `Nassarawa` →
  `Nasarawa`, `Abuja` / `Federal Capital Territory` → `FCT`. Where there is none, the state is
  resolved from the LGA via `src/nigeria-lgas.js`, exactly as alert targets are:
  | Authority | Result |
  | --- | --- |
  | an LGA name in exactly one state (764 of the 770) | that state, both names re-spelled canonically — who gets texted does not change |
  | an LGA name plus a state it really is in | that pair, canonically spelled |
  | an LGA name in two states (`Bassa`, `Ifelodun`, `Irepodun`, `Nasarawa`, `Obi`, `Surulere`) and no state | **skipped**, naming the contact, its phone and the candidate states |
  | a state that is not a Nigerian state | **skipped** (it used to become `null`, which the database now rejects) |
  | an LGA that is in no state, or an LGA that is not in the state given | **skipped**, naming the contact and why |

  Nothing is guessed: there is no "all states" coverage to fall back on, and picking one of two
  candidate states would text an emergency desk about a place it does not serve. Skipped contacts
  are listed in the run report — add each one by hand under **Admin → Authorities**, choosing the
  LGA under the state that desk actually serves.
- **Alert targets:** `alerts.target_state` is mandatory whenever `target_lga` names an LGA
  (migration `20260927080000`), because LGA names repeat across states. Firestore alerts only
  carried an LGA name, so the state is resolved from the canonical LGA table
  (`src/nigeria-lgas.js`, generated from the app's `nigeria_locations_data.dart`):
  | Alert | Result |
  | --- | --- |
  | `targetLga` empty / `'All'` (any casing) | `target_lga = 'All'`, `target_state` = the alert's own state if it has one, else `null` (everyone) |
  | an LGA name in exactly one state | that state, both names re-spelled canonically |
  | an LGA name in two states (`Bassa`, `Ifelodun`, `Irepodun`, `Nasarawa`, `Obi`, `Surulere`), and the alert's creator has a profile state that is one of them | that state, with a warning saying it was taken from the creator |
  | an LGA name in two states with no usable creator state | **skipped**, naming the alert, the LGA and the candidate states |
  | an LGA name that is in no state, or a state/LGA pair that does not exist | **skipped**, naming the alert and why |

  Nothing is guessed and an alert is never widened to `'All'` or to a whole state to make it fit —
  that would broadcast it to people it was not addressed to. Skipped alerts are listed in the run
  report; re-create each one in the admin panel with the state you meant.
- **Verification overrides:** actions map to `approved | rejected | verified`. An override whose validator
  was not migrated is kept with `validator_id = null` and a warning.
- **Missing reports:** an alert whose report does not exist in Supabase (not migrated, or its write failed)
  is kept with `report_id = null` and a warning. Verifications and overrides of such a report are skipped.
- **Timestamps:** Firestore Timestamps, serialized `{_seconds}`, ISO strings (for example `reports.submittedAt`,
  `messages.sentAt`, `users.lastLoginAt`) and epoch numbers are all accepted.
- **Phone accounts:** Firebase Auth emails of the form `<digits>@ewer.phone` become Supabase phone users
  (`phone: '+<digits>'`, `phone_confirm: true`).

All of these rules live in [`src/transform.js`](src/transform.js). They are pure functions,
unit-tested in [`test/transform.test.js`](test/transform.test.js).

## Prerequisites

1. **Node.js 22+**.
2. **Supabase schema applied** to the target project. From the repo root:
   `supabase link --project-ref <ref>` and then `supabase db push`. This also creates the storage buckets.
3. **Stop the backend during the import.** In Railway, scale the backend service to **0 replicas**
   (or remove its active deployment) before `--apply`, and scale it back up afterwards. Database
   triggers queue `report_created`, `report_status_changed` and `alert_created` events in
   `notification_outbox` while rows are inserted, and create `scheduled_escalations` for pending
   reports. The script neutralises those after every step, but a running worker polls every few
   seconds and would push them to real users first. `--apply` is refused unless you also pass
   `--i-stopped-the-backend` to confirm this.
4. **A Firebase service-account key** for `ewer-8f788`, from Firebase console → Project settings →
   Service accounts → Generate new private key. It needs to read Auth, Firestore and Storage.
   Keep the key outside git. `.gitignore` already excludes common key filenames.
5. **The Supabase service-role key.** It bypasses RLS, so keep it secret.
6. In Supabase Auth, **enable the Phone provider** (with an SMS provider) so migrated phone users
   can sign in with OTP. **Configure custom SMTP** before `--send-password-resets`, because the built-in
   mailer allows only a few emails per hour. Add your reset landing page to *Redirect URLs*.
7. **Disable new sign-ups in Supabase** (Authentication → Sign In / Providers → turn off
   "Allow new users to sign up") for the whole migration window, and re-enable them after cut-over.
   Otherwise someone can register a migrated user's email or phone first; the script refuses to link
   such accounts (see *Users*) and stops, and you have to resolve each conflict by hand.
8. Ideally, **freeze writes to Firebase** during the final run: ship the Supabase app build, or put the
   old app into maintenance. Otherwise, re-run the script right before cut-over to pick up late changes.

## Steps

```bash
cd migration/firebase-to-supabase
npm install
cp .env.example .env        # then fill in the values
npm test                    # unit tests for the transforms

# 1. Dry run. Reads Firebase only; also reads Supabase (read-only) when configured.
node src/migrate.js
node src/migrate.js --only=reports,verifications --samples=5

# 2. Review the output: counts, sample rows, skipped rows and warnings.
#    The full detail is also written to migration-report-<timestamp>.json.

# 3. Stop the backend (Railway: scale to 0), then apply.
node src/migrate.js --apply --i-stopped-the-backend

# 4. Check the validation report printed at the end. Spot-check in the Supabase dashboard.

# 5. Optional: email users a link to set a new password (see below).
node src/migrate.js --apply --i-stopped-the-backend --only=none --send-password-resets

# 6. Scale the backend back up.
```

### Flags

| Flag | Meaning |
| --- | --- |
| *(none)* | Dry run: no writes to Supabase, Storage or the state file |
| `--apply` | Perform the writes. Requires `--i-stopped-the-backend` |
| `--i-stopped-the-backend` | Confirms the backend worker is stopped (Railway: scaled to 0) for the import |
| `--only=a,b,c` | Run only these steps: `users` (alias `profiles`), `storage`, `knowledge_base`, `authorities`, `reports`, `alerts`, `verifications`, `verification_overrides`, `messages`, `contacts`, `trusted_devices`, `login_history`, `ndpa_consents`, or `none` |
| `--skip-storage` | Don't copy Storage objects. URLs of objects not copied by an earlier run keep pointing at Firebase |
| `--send-password-resets` | After the import, send a Supabase password-reset email to every migrated, non-disabled email user (throttled by `RESET_THROTTLE_MS`). Sent addresses are recorded, so re-runs don't send again |
| `--state-file=path` | Use a state file other than `./migration-state.json` |
| `--samples=N` | Number of sample transformed rows to print per table (default 2) |

Steps always run in dependency order: users → storage → profile patch → knowledge_base,
authorities → reports → alerts → verifications → *report finalize* → verification_overrides →
messages, contacts, trusted_devices, login_history, ndpa_consents. Alerts run after reports,
so an alert's `reportId` can resolve to the migrated report.

## How it works

### Users and the password situation

Firebase stores passwords as its own modified-scrypt hashes, which Supabase Auth cannot import.
Each user is therefore created with `auth.admin.createUser` and a **random password nobody knows**:

- **Email users:** `email_confirm` = Firebase `emailVerified` || Firestore `users.isVerified`.
  They set a new password with the reset email (`--send-password-resets`) or with "Forgot password"
  in the app. Tell users about this before cut-over.
- **Phone users** (`<digits>@ewer.phone`): created with `phone: '+<digits>'` and `phone_confirm: true`.
  They sign in with an SMS OTP and need no password.

Creating the user fires `handle_new_user`, which builds the profile from `user_metadata`
(name, role, state, lga, ward, phone, address). The trigger caps the role at non-admin, so the script
then **updates the profile** with the real values: role, is_approved, is_disabled, is_verified,
biometrics_enabled, monitoring_zone, profile_image_url, registration_code, last_login_at,
created_at and legacy_firebase_uid.
Users whose Firestore `isDisabled` is true (or who are disabled in Firebase Auth) are also **banned**
(`ban_duration: '876000h'`); every other migrated user has any ban **lifted** (`ban_duration: 'none'`),
so the Auth ban always matches `is_disabled`.

Every account the script creates carries `app_metadata.migrated_from_firebase = true` (plus
`firebase_uid`). If an email or phone number is already registered in Supabase, the script only
reuses that account when it carries this marker (a re-run with a lost state file) **or** the matched
email/phone is **confirmed** and the account was **created before the migration started** (the
first `--apply` run recorded in the state file). Anything else — e.g. an unconfirmed sign-up, or
one made during the migration window — could be someone claiming a migrated user's address, so the
run **stops before creating any user** and lists each conflict for a manual decision (delete the
Supabase account if it is not the same person, or have the owner confirm it, then re-run). A dry
run with Supabase configured lists the same conflicts as `CONFLICT` warnings. If two Firebase accounts share an email, both map to one Supabase
user; the first profile is kept and the other is listed as a warning. Firebase accounts with no
email and no phone are skipped.

### Idempotency and the state file

- `profiles.legacy_firebase_uid`, `reports.legacy_firebase_id` and `knowledge_base.legacy_firebase_id`
  are the idempotency keys for those tables. At start-up the script also reads them from Supabase,
  so losing the state file does not cause duplicates.
- A report keeps its Firestore id as its UUID when that id is a valid UUID. Otherwise a UUID is
  generated and recorded.
- `authorities`, `alerts`, `verification_overrides`, `messages`, `contacts` and `login_history` have
  no legacy column. Their Firestore id → UUID mapping is kept in **`migration-state.json`** (gitignored)
  and rows are upserted on `id`. **Back this file up after an apply run.** Without it, a re-run inserts
  those tables again.
- `verifications`, `trusted_devices` and `ndpa_consents` upsert on their natural unique keys. Existing rows
  are updated, so a re-run applies changes made in Firebase since the last run (a changed vote fires
  `verifications_after_update`, which the report finalize step and side-effect suppression handle like inserts).
- Copied Storage objects are recorded in the state file, so they are not copied again.
- Ids are saved to the state file **before** rows are written, so a crash can't create a second id
  for the same document.

### Side-effect suppression

1. Before writing, the script records `max(notification_outbox.id)` in the state file (the baseline is
   logged). Suppression starts from the **lowest baseline of any run** in the state file, and matches
   **every report and alert id in the state file** (plus every report with a legacy id), not only this
   run's. So if a run is killed before its final suppression, the next `--apply` run (even with
   `--only=none`) neutralises the events it left behind.
   Keep the backend stopped from the first `--apply` run until the last one: an event a real user
   triggered on an imported report in between, and that the backend has not processed yet, would
   also be suppressed.
2. Alerts are inserted with `is_active = false`, so no `alert_created` event is queued. `is_active` is
   then restored; alerts have no update trigger. An alert that cannot be re-activated is listed as a
   warning and left inactive; the run continues.
3. **Report finalize.** Two things can change a report during import. The verifications trigger
   recomputes `verification_count` and can move a report to `verified`. The reports insert trigger
   rewrites `escalation_scheduled_at` and `escalation_status`. After verifications are imported, each
   report's workflow columns (status, verified_at, auto_validated, approved/rejected/escalated
   fields) are set back to the Firestore values with plain `UPDATE`s. `verification_count` is not
   taken from Firestore: it is then recounted from the imported confirmed verifications, the same
   way the database triggers maintain it.
4. After **each** writing step (reports, alerts, verifications, report finalize) and once more at the
   end (in a `finally` block, so this also runs after a failure, and on **Ctrl-C / SIGTERM**: the run stops
   after the current request, saves the state file, suppresses, then exits; a second signal exits at once):
   - every not-yet-processed `notification_outbox` row with `id > baseline` **whose payload
     `report_id` / `alert_id` is an imported report or alert** gets `processed_at = now()` and
     `last_error = 'migration import'`. Events of real users created during the import are left alone;
   - every `pending` `scheduled_escalations` row for an imported report becomes
     `status = 'skipped'`, `reason = 'migration import'`.

   This narrows the window but does not close it, which is why the backend must be stopped (see
   Prerequisites). The logic is in [`src/sideEffects.js`](src/sideEffects.js), tested in
   [`test/sideEffects.test.js`](test/sideEffects.test.js).

### Storage

Every object under `report_images/` and `profile_images/` is downloaded and uploaded to
`report-images` or `profile-images` at `{newUserId}/{rest of path}`. Both buckets accept only
`image/jpeg`, `image/png`, `image/webp` and `image/heic` up to 5 MB. `image/jpg` is uploaded as
`image/jpeg`, and a missing or generic type (`application/octet-stream`) is inferred from the file
extension. Objects of any other type, or larger than 5 MB, are not copied: they are listed under
*Skipped — storage* (in the dry run too) and a note says that the row URLs referencing them could not
be rewritten. Row URLs are rewritten by matching the decoded object path inside Firebase download URLs
(`firebasestorage.googleapis.com/v0/b/…/o/…`, `storage.googleapis.com`, `gs://`). http(s) URLs that point
elsewhere, or at objects that were not copied, are left unchanged. `gs://` references that could not be
rewritten are dropped with a warning (the app cannot load them), as are local file paths saved by old
app versions.

## Validation report

The run ends with a table of **source count / ready / skipped / written / target rows** per table,
followed by skipped rows and warnings grouped by reason, with example ids. Examples:

- `report X not migrated` (verification of a deleted report)
- `reporter uid not migrated; user_id set to null`
- `unknown severity`

The complete list is written to `migration-report-<timestamp>.json`.

## Rollback

The import only adds data to Supabase; Firebase is never modified. To undo it before go-live,
the simplest option is to reset the target project: `supabase db reset --linked`, then
`supabase db push`, then empty the two buckets. That wipes the whole database, including any auth
users you created by hand.

To remove only the migrated data (SQL editor, as `postgres`):

```sql
-- Report-linked rows cascade from reports; user-owned rows cascade from profiles.
delete from public.alerts where report_id in (select id from public.reports where legacy_firebase_id is not null);
delete from public.reports where legacy_firebase_id is not null;
delete from public.knowledge_base where legacy_firebase_id is not null;
-- auth.users → profiles → verifications, overrides, messages, contacts,
-- trusted_devices, login_history and ndpa_consents all cascade.
delete from auth.users where id in (select id from public.profiles where legacy_firebase_uid is not null);
```

Delete `authorities` and admin-created `alerts` rows by the ids in `migration-state.json`
(`ids.authorities`, `ids.alerts`). Remove the copied objects from the `report-images` and
`profile-images` buckets. Then delete `migration-state.json` before trying again.

## Development

```bash
npm test     # node:test unit tests
```

- `src/transform.js`: pure mapping and normalisation functions (tested).
- `src/migrate.js`: the runner (I/O and ordering).
- `src/clients.js`: env loading, Firebase Admin and Supabase clients, paginated readers.
- `src/state.js`: the `migration-state.json` store.
- `src/sideEffects.js`: outbox / escalation suppression (tested).
- `src/lifecycle.js`: SIGINT/SIGTERM handling (tested).
- `src/steps.js`: Supabase-side step helpers: alert re-activation, report existence checks (tested).
- `src/builtinContent.js`: titles of the seeded built-in guides (tested against the SQL).
- `src/nigeria-lgas.js`: **generated** — the 36 states + FCT and their 770 LGAs, in the canonical
  spellings `public.nigeria_states` / `public.nigeria_lgas` store. Regenerate with
  `node scripts/gen-nigeria-lgas.mjs` after changing the app's
  `lib/core/data/nigeria_locations_data.dart`; `test/nigeria-lgas.test.js` fails if the two drift.
