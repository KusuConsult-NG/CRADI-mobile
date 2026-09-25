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
| `authorities` | `authorities` | `coverageLGA` / `lga` → `coverage_lga` |
| `reports` | `reports` | legacy statuses and severities are normalised. `legacy_firebase_id` holds the Firestore id |
| `alerts` | `alerts` | `targetLga` → `target_lga`. A `createdBy` of `'admin'` → `null` |
| `verifications` | `verifications` | upsert on `(report_id, verifier_id)` |
| `verification_overrides` | `verification_overrides` | `timestamp` → `created_at` |
| `messages` | `messages` | ISO `sentAt` → `sent_at` |
| `contacts` | `contacts` | |
| `trusted_devices` | `trusted_devices` | upsert on `(user_id, device_fingerprint)` |
| `login_history` | `login_history` | `timestamp` → `occurred_at` |
| `ndpa_consents` | `ndpa_consents` | `uid` (or the doc id) → `user_id` |

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
3. **The backend must NOT be running during the import, or OneSignal must not be configured
   yet.** Database triggers queue `report_created`, `report_status_changed` and `alert_created` events in
   `notification_outbox` while rows are inserted. The script marks those events as processed when
   it finishes, but a worker running at the same time could send them first.
4. **A Firebase service-account key** for `ewer-8f788`, from Firebase console → Project settings →
   Service accounts → Generate new private key. It needs to read Auth, Firestore and Storage.
   Keep the key outside git. `.gitignore` already excludes common key filenames.
5. **The Supabase service-role key.** It bypasses RLS, so keep it secret.
6. In Supabase Auth, **enable the Phone provider** (with an SMS provider) so migrated phone users
   can sign in with OTP. **Configure custom SMTP** before `--send-password-resets`, because the built-in
   mailer allows only a few emails per hour. Add your reset landing page to *Redirect URLs*.
7. Ideally, **freeze writes to Firebase** during the final run: ship the Supabase app build, or put the
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

# 3. Apply.
node src/migrate.js --apply

# 4. Check the validation report printed at the end. Spot-check in the Supabase dashboard.

# 5. Optional: email users a link to set a new password (see below).
node src/migrate.js --apply --only=none --send-password-resets
```

### Flags

| Flag | Meaning |
| --- | --- |
| *(none)* | Dry run: no writes to Supabase, Storage or the state file |
| `--apply` | Perform the writes |
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
(`ban_duration: '876000h'`).

If an email or phone number is already registered in Supabase (a re-run, or a tester account),
the script reuses that user. If two Firebase accounts share an email, both map to one Supabase
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
- `verifications`, `trusted_devices` and `ndpa_consents` upsert on their natural unique keys.
- Copied Storage objects are recorded in the state file, so they are not copied again.
- Ids are saved to the state file **before** rows are written, so a crash can't create a second id
  for the same document.

### Side-effect suppression

1. Before writing, the script records `max(notification_outbox.id)` (the baseline is logged).
2. Alerts are inserted with `is_active = false`, so no `alert_created` event is queued. `is_active` is
   then restored; alerts have no update trigger.
3. **Report finalize.** Two things can change a report during import. The verifications trigger
   recomputes `verification_count` and can move a report to `verified`. The reports insert trigger
   rewrites `escalation_scheduled_at` and `escalation_status`. After verifications are imported, each
   report's workflow columns (status, verification_count, verified_at, auto_validated,
   approved/rejected/escalated fields) are set back to the Firestore values with plain `UPDATE`s.
4. At the end (in a `finally` block, so this also runs after a failure):
   - every `notification_outbox` row with `id > baseline` that is not yet processed gets
     `processed_at = now()` and `last_error = 'migration import'`;
   - every `pending` `scheduled_escalations` row for an imported report becomes
     `status = 'skipped'`, `reason = 'migration import'`.

### Storage

Every object under `report_images/` and `profile_images/` is downloaded and uploaded to
`report-images` or `profile-images` at `{newUserId}/{rest of path}`. The content type is inferred from
the file extension when Firebase recorded a generic type. Row URLs are rewritten by matching the
decoded object path inside Firebase download URLs (`firebasestorage.googleapis.com/v0/b/…/o/…`,
`storage.googleapis.com`, `gs://`). URLs that point elsewhere, or at objects that were not copied,
are left unchanged. Local file paths saved by old app versions are dropped.

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
npm test     # node:test unit tests for src/transform.js
```

- `src/transform.js`: pure mapping and normalisation functions (tested).
- `src/migrate.js`: the runner (I/O and ordering).
- `src/clients.js`: env loading, Firebase Admin and Supabase clients, paginated readers.
- `src/state.js`: the `migration-state.json` store.
