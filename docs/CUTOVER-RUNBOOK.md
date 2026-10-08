# Production Cutover Runbook: Supabase → Appwrite Cloud

**Target System:** Appwrite Cloud (`fra.cloud.appwrite.io`)  
**Project ID:** `6ac51e70002ab6238fec`  
**Database ID:** `cradi`  
**Region:** Frankfurt (`fra`)  
**SMS Gateway:** Termii Nigeria (`generic` route)  
**Push Providers:** Firebase Cloud Messaging (`fcm`), Apple Push Notification service (`apns`)  
**Functions:** `client` (user operations), `worker` (triggers & SMS outbox drain)  

---

## 1. Cutover Architecture & Strategy

This runbook specifies the end-to-end, deterministic procedure for executing the production cutover from Supabase (Postgres RLS, Supabase Auth, Storage) and OneSignal to Appwrite Cloud and Appwrite Messaging.

### Core Architecture Invariants
1. **Identities Before Documents:** Document ACLs in Appwrite reference users (`user:<uuid>`), role labels (`label:<role>`), and ward teams (`team:<teamId>`). In Appwrite, an ACL referencing an uncreated team or label is silently accepted without granting access to anyone. Therefore, identity seeding MUST run before document migration.
2. **Postgres UUID Preservation:** User IDs and document IDs preserve Postgres 36-character UUID strings verbatim (`p.id` -> `userId`, `docId`). No stripped dashes, no translation layers.
3. **Write-Time ACL Materialization:** Postgres RLS computed access dynamically at query time based on `profiles`. Appwrite enforces permissions at document read time based on the ACL stamped during write.
4. **Visibility Parity (Reconciliation Gate):** Row count equivalence is insufficient. The cutover cannot proceed without `reconcile.mjs` confirming per-user visibility parity across roles.
5. **Zero Data Destruction:** The migration is additive and read-only against Supabase. Supabase remains in an intact read-only state throughout the process until decommissioned.

---

## 2. Roles, Prerequisites & Environment Setup

### Roles
- **Lead Operator:** Executes CLI scripts, migrations, and CI workflows.
- **Database Administrator:** Manages Supabase write freeze, connection strings, and backups.
- **Communications Lead:** Alerts field agents, LDP coordinators, and response teams.

### Required Credentials & Tools
Ensure the following credentials are ready in the Operator's environment (never commit to git):
**Two sets of names, both needed.** The migration scripts under
`docs/appwrite-spike/migrate` read `AW_*`; the tooling under `infra/appwrite`
(`verify.mjs`, `cloud-check.mjs`, `provision.mjs`, `plan.mjs`) reads
`APPWRITE_*`. Export both or the Phase 0 checks fail on an unset variable while
the Phase 2 scripts are fine, which reads like a broken tool rather than a
missing export.

```bash
# Consumed by infra/appwrite/*.mjs (Phase 0, provisioning, hotfixes)
export APPWRITE_ENDPOINT="https://fra.cloud.appwrite.io/v1"
export APPWRITE_PROJECT_ID="6ac51e70002ab6238fec"
export APPWRITE_API_KEY="<APPWRITE_SERVER_API_KEY>"  # database, users, teams, functions, storage scopes
export APPWRITE_FN_CLIENT="client"                   # cloud-check.mjs only; 'client' is the default

# Consumed by docs/appwrite-spike/migrate/*.mjs (Phases 2-4)
export AW_ENDPOINT="$APPWRITE_ENDPOINT"
export AW_PROJECT="$APPWRITE_PROJECT_ID"
export AW_KEY="$APPWRITE_API_KEY"
export PG_URL="<SUPABASE_POSTGRES_DIRECT_URL>"       # Direct connection (port 5432 or 6543)
# No MIGRATION_PASSWORD. 5.1 chose to import the bcrypt hashes, so no script
# here knows or sets anybody's password; `reconcile.mjs` mints a session with
# AW_KEY instead of signing in. If you find the variable still exported from an
# earlier run, unset it — nothing reads it, and it reads like a live secret.

# Consumed by the worker Function, set in the Appwrite console, not here
export TERMII_API_KEY="<TERMII_API_KEY>"
export TERMII_SENDER_ID="CRADI"
```

Do **not** export `APPWRITE_BUCKET_ID`. `verify.mjs` treats it as a signal that
the project is on a one-bucket tier; with it set, the verifier checks a
single-bucket plan and can report that the project matches while neither planned
bucket exists. It prints a note when it sees the variable — heed it.

### Which database, and the one thing Phase 0 cannot prove

`APPWRITE_DATABASE_ID` decides this, and **five components resolve it
independently, each defaulting to `cradi`**:

| | variable | set where |
|---|---|---|
| the two Functions | `APPWRITE_DATABASE_ID` | per Function, in the console |
| admin, server side | `APPWRITE_DATABASE_ID` | hosting env |
| admin, browser side | `NEXT_PUBLIC_APPWRITE_DATABASE_ID` | hosting env |
| Flutter app | `APPWRITE_DATABASE_ID` | `env.json` — **compile-time**, baked into the APK |
| migration scripts | `APPWRITE_DATABASE_ID` | the operator's shell |

Leave it unset everywhere and all five agree on `cradi`, which is the simplest
thing that can be correct. Set it in some places and not others and the data
sits in one database while the app reads another — which Appwrite answers with
`200 {"total": 0}`: an empty app, and no error anywhere.

**`verify.mjs` cannot catch that**, and the reason is worth stating plainly:
`plan.mjs` takes its `DATABASE_ID` from the same variable. So a passing verify
means "the database this variable names matches the plan" — never "this is the
database the app reads". The two are indistinguishable in its output.
`phase0.mjs` therefore reports the resolved database, says whether a `cradi`
also exists alongside it, and lists all five places that must agree.

`6941e2c2003705bb5a25` was the *previous* Cloud project's database. If it is in
use in the current project, that is a deliberate choice and every one of the five
must carry it; if it is a leftover export, unset it before anything writes.

There is no `AW_DATABASE_ID`: nothing reads that name.

Install the migration scripts' dependency once:
```bash
cd docs/appwrite-spike/migrate && npm install && cd -
```

Verify the local environment has Node.js 22 or newer, PostgreSQL client tools
(`psql`), and **Flutter 3.47.5** — the version pinned in `.fvmrc` and in all
three `flutter-action` steps of `.github/workflows/ci.yml`, not merely "3.24 or
newer". CI runs `dart format --set-exit-if-changed .` as the *first* step of
`Flutter Analyze & Test`, and an older formatter disagrees with a newer one on
code neither of you wrote: it reformats files your change never touched, the
format step fails, and `flutter analyze` and `flutter test` are then **skipped**
rather than run — so the job goes red with the two checks that matter never
having executed. Match the pin.

---

## 3. Phase 0: Pre-Flight Audit & Infrastructure Verification

Execute these pre-flight checks at least 24 hours prior to the scheduled cutover window.

### 3.1 Appwrite Cloud Infrastructure Check

One command, from the repository root, with the `APPWRITE_*` variables from
section 2 in the environment:

```bash
node infra/appwrite/phase0.mjs
```

It runs the preflight, then `verify.mjs`, then `cloud-check.mjs`, stopping at the
first failure. **It writes no migrated data** — it does not run
`seed-identities.mjs`, `copy-tables.mjs` or `copy-storage.mjs`, which are the
migration itself and need both a write freeze and the password decision in 5.1.
On its own, Phase 0 changes nothing you would have to undo.

Exit codes mean different things and the difference matters: **2** is not
configured or not reachable — nothing was contacted, so it says nothing about the
project. **1** is a check that failed. **0** is ready for Phase 1.

- **Preflight.** Are the three variables set, and does `/health/version` answer
  as Appwrite? That endpoint needs no key, so a failure there is the network or
  the URL and nothing else. It is a separate step because the failure modes are
  confusable and expensive: an egress policy that does not list the host answers
  with *its own* 403 and *its own* body, which reads like a wrong endpoint, which
  reads nothing like a rejected key — and only the last is about the project. The
  run relays whatever actually answered rather than guessing. It also refuses to
  start while `APPWRITE_BUCKET_ID` is set, because `plan.mjs` still reads it as
  the single-bucket id and a stale value describes a bucket no provisioning run
  ever made.
- **`verify.mjs`** — does the live project match `plan.mjs`? Read-only.
  *Criteria:* no differences. Unplanned extras are listed without changing the
  exit code, so read the output and not only the code.
- **`cloud-check.mjs`** — does the project *behave*? Eight probes that need a
  write to answer, including that a label-gated collection is unreadable without
  the label. Everything it creates is named `cloudchk-<stamp>` and deleted at the
  end, including after a failure. If it reports that cleanup failed, remove the
  rows it names before running anything else.
  *Criteria:* 8/8 pass, cleanup clean.

This is also the step that answers the one question the test harness in
`docs/appwrite-spike/migrate` cannot: that harness models how Appwrite evaluates
ACLs — table permissions, and a row's own only where row security is on — and
only Appwrite can confirm the model. Run the pieces individually if you need to
(`node infra/appwrite/verify.mjs`, `node infra/appwrite/cloud-check.mjs`);
`--single-bucket` passes through to `verify.mjs`.

### 3.2 Push Providers Status in Appwrite Console
Navigate to **Appwrite Cloud Console** -> **Project Settings** -> **Messaging**:
1. **FCM Provider (`fcm`):** Verify status is **Enabled**. The service account
   JSON must belong to Firebase project **`ewer-8f788`** — that is the
   `project_id` in `android/app/google-services.json` and the `PROJECT_ID` in
   `ios/Runner/GoogleService-Info.plist`. (It is not `cradi-mobile`; that name
   appears nowhere in the Firebase configuration.)
2. **APNs Provider (`apns`):** as of the last check this is **registered but not
   enabled**, pending the Apple `.p8` key, Key ID and Team ID — see
   `docs/DEPLOYMENT.md` section 1d. iOS push therefore needs two things, not
   one: this provider enabled *and* the `GoogleService-Info.plist` linked into
   the Runner target. Do not record "Enabled" unless the console says so.
3. Test target registration:
   ```bash
   node infra/appwrite/push-smoke-test.mjs
   ```
   *Criteria:* the target is created **and comes back carrying the provider it
   was sent with** — the script asserts this, because Appwrite files a target
   with no `providerId` under the project's default provider, which looks
   correct while FCM is the only one enabled and silently misroutes every iOS
   target the day APNs is turned on.

### 3.3 Source Data Audit (`auth.users` & `profiles`)
Run the following SQL audit against the Supabase database to catch any edge cases that would break Appwrite account creation:

```sql
-- 1. Check for null or empty emails in auth.users
SELECT id, email, created_at 
FROM auth.users 
WHERE email IS NULL OR trim(email) = '';

-- 2. Check for duplicate emails (case-insensitive collisions)
SELECT lower(trim(email)) AS normalized_email, count(*) 
FROM auth.users 
GROUP BY lower(trim(email)) 
HAVING count(*) > 1;

-- 3. Check for profiles without corresponding auth.users
SELECT p.id, p.name, p.role 
FROM profiles p 
LEFT JOIN auth.users u ON u.id = p.id 
WHERE u.id IS NULL;

-- 4. Check Nigerian phone number format compatibility (+234 format required by Termii)
SELECT id, phone 
FROM profiles 
WHERE phone IS NOT NULL 
  AND phone !~ '^\+234[0-9]{10}$';

-- 5. Check ward naming length (Appwrite team ID limit is 36 chars)
SELECT distinct state, lga, ward, length('ward_' || lower(regexp_replace(state || '_' || lga || '_' || ward, '[^a-zA-Z0-9_]', '_', 'g'))) as len
FROM profiles
WHERE ward IS NOT NULL
ORDER BY len DESC;
```

**Remediation Steps:**
- If duplicate emails exist: coordinate with account owners to deduplicate prior to the freeze.
- If invalid phone numbers exist: normalize to E.164 (`+234...`) before identity seeding.
- Ward teams: verify the `wardTeam(state, lga, ward)` slugifier in `functions/cradi/src/lib/appwrite.js` handles lengths over 36 characters using hashing/truncation (already verified across all 584 Nigerian pilot wards).

---

## 4. Phase 1: Write Freeze & Maintenance Mode

### 4.1 Advance Communication
Send broadcast notice to field agents 2 hours before the cutover window:
> *"Scheduled maintenance in progress. Incident reports submitted via the mobile app will be stored safely in local offline storage on your device and automatically synced once maintenance completes."*

### 4.2 Enable Maintenance Mode on Admin Portal
Deploy maintenance banner on `CRADI-Mobile-Admin` or set environment variable:
```bash
NEXT_PUBLIC_MAINTENANCE_MODE=true
```

### 4.3 Supabase Database Write Freeze
Lock all public writes on Supabase while keeping read access available for the
migrator. Do this with `REVOKE`, not with policies:

```sql
-- Grants are checked before RLS, so this is unambiguous and reversible.
REVOKE INSERT, UPDATE, DELETE ON
  public.reports, public.verifications, public.profiles,
  public.alerts, public.authorities, public.app_settings
FROM anon, authenticated;
```

> **Why not a policy.** An earlier version of this runbook froze writes with
> `CREATE POLICY freeze_reports_write ON reports FOR INSERT WITH CHECK (false)`.
> That does not freeze anything. Postgres RLS policies are **permissive** by
> default and permissive policies combine with **OR**, so adding one that
> permits nothing leaves every existing policy still granting what it granted —
> writes continue, `psql` reports `CREATE POLICY`, and the operator believes the
> database is sealed. Any row written during that window is then migrated or not
> depending on when the migrator happened to read, and nothing reports a
> problem. If you want the policy form, it must be `AS RESTRICTIVE` (which is
> AND-ed); `REVOKE` is simpler and harder to get subtly wrong.

Verify the freeze rather than assuming it, as a non-superuser role:
```sql
-- Expect: permission denied for table reports
SET ROLE authenticated;
INSERT INTO public.reports (id) VALUES (gen_random_uuid());
RESET ROLE;
```

### 4.4 Drain Queues & Record Baseline Row Counts
Ensure no background tasks are in-flight. There is no `sms_queue` table — the
two that matter are `notification_outbox` (pending work is `processed_at is
null`, there is no `status` column) and `sms_deliveries`:
```sql
-- Outbox must be fully drained before migrating.
SELECT count(*) AS unprocessed FROM public.notification_outbox
WHERE processed_at IS NULL;

-- Any row still 'claimed' is an SMS the worker took and never resolved.
SELECT status, count(*) FROM public.sms_deliveries GROUP BY status;
```

Record snapshot counts to verify against migrated totals:
```sql
SELECT 'profiles' AS tbl, count(*) FROM profiles
UNION ALL
SELECT 'reports', count(*) FROM reports
UNION ALL
SELECT 'verifications', count(*) FROM verifications
UNION ALL
SELECT 'authorities', count(*) FROM authorities
UNION ALL
SELECT 'alerts', count(*) FROM alerts
UNION ALL
SELECT 'app_settings', count(*) FROM app_settings;
```
Save these numbers in your cutover execution log.

---

## 5. Phase 2: Appwrite Identity Seeding

### 5.1 Everyone keeps their own password — and you get exactly one chance

> **Prerequisite, and the one that was missed.** The hashes must actually be in
> the database `PG_URL` points at. `sync-supabase.mjs` builds its mirror of
> `auth.users` from `GET /auth/v1/admin/users`, and that API **does not return
> `encrypted_password`** — so a mirror built without `SUPABASE_DB_URL` has the
> column and no values, and `seed-identities.mjs` would create every account
> without a password while reporting success. That is exactly how the live
> project ended up with accounts nobody had the password to.
>
> Either point `PG_URL` at the Supabase Postgres directly (port 5432, or the
> 6543 pooler — not the project URL, and a service key will not do), or re-run
> `sync-supabase.mjs` with `SUPABASE_DB_URL` set, which mirrors the hashes and
> says how many it carried. Confirm before going further:
>
> ```bash
> psql "$PG_URL" -tAc "select count(*) filter (where encrypted_password ~ '^\\\$2[aby]\\\$') as bcrypt,
>                             count(*) filter (where coalesce(encrypted_password,'') = '') as none
>                        from auth.users"
> ```
>
> `seed-identities.mjs` now refuses to run when every row is empty, and
> `reseed-passwords.mjs` refuses a delete that would import fewer passwords than
> the accounts already hold. Neither refusal is a substitute for checking.

`seed-identities.mjs` imports each account's bcrypt hash from
`auth.users.encrypted_password`, so every user keeps the password they already
have and nobody has to be told anything. There is no `MIGRATION_PASSWORD` and no
shared secret: no script in this repository knows any user's password.

How it decides, per row:

| `auth.users.encrypted_password` | endpoint | result |
| --- | --- | --- |
| bcrypt (`$2a$`/`$2b$`/`$2y$`) | `POST /users/bcrypt` | the user's own password still works |
| null or empty | `POST /users` | a passwordless account, which is what an OAuth-only or magic-link-only user had |
| anything else | `POST /users` | account created, **counted as a failure**, id named — that user has lost their password and nobody would otherwise notice |

The summary's `passwords` block is the thing to read: `imported`, `none`,
`notBcrypt`, `alreadyExisted`.

> **This step does not converge on a re-run, and it is the only one that does
> not.** Appwrite takes a hash at creation and nowhere else — `POST /users/bcrypt`
> and `POST /users/scrypt` and friends are creation endpoints, and
> `PATCH /users/{userId}/password` accepts a **plaintext** only. There is no API
> that sets a pre-existing hash on an existing account. So if an account is
> already there, the seeder gets a 409, the hash is **not** imported, and the
> account keeps whatever password the run that created it gave it. The seeder
> counts those under `passwords.alreadyExisted` and names every one of them in
> `failures` with "the bcrypt hash was NOT imported". A re-run that reports
> `imported: 0, alreadyExisted: 650` has changed nothing.

**If accounts already exist with a shared password** — because an earlier
rehearsal of this runbook ran the pre-import seeder against the project — the
only way to the hashes is to delete and re-create. `reseed-passwords.mjs` does
it, and it audits before it touches anything:

```bash
cd docs/appwrite-spike/migrate
node reseed-passwords.mjs          # audit: reads only, changes nothing
```

The audit prints how many accounts exist, how many of them the seeder created,
how many have a live session, how many have a password today, and what
re-seeding would import. It exits 1 on anything you must decide first — read
those findings before going on.

**The finding that matters most is a `STOP:`.** It means re-seeding would import
fewer passwords than the accounts hold now, so the delete would leave people
unable to sign in at all — worse than a shared password, and irreversible, since
the accounts are the only place that password exists. The cause is almost always
the mirror above. `--delete` refuses outright in that case, whatever
`CONFIRM_DELETE_USERS` says; `--accept-password-loss` overrides it only for a
project whose users genuinely have no password to keep.

Once the audit is clean:

```bash
CONFIRM_DELETE_USERS=<the number the audit printed> \
  node reseed-passwords.mjs --delete
node seed-identities.mjs           # re-creates them, with their own hashes
```

Expect `passwords.alreadyExisted: 0` from that last run. Anything else means an
account survived the delete and kept its old password.

Three properties worth knowing, because this is the one destructive step in the
runbook:

- **It deletes only accounts whose id is a Postgres profile id.** That is how
  the seeder names them, so anything else is a real sign-up made after the
  migration, or an account somebody created by hand. The audit reports those and
  the delete skips them — but if any exists, the app may already be live, which
  is what the third point is about.
- **The count is an interlock.** `CONFIRM_DELETE_USERS` must equal what the run
  itself counts, or nothing is deleted. A command copied from an earlier audit,
  or aimed at a project with a different population, stops rather than deleting
  a set nobody looked at.
- **A live session is a finding, not a footnote.** A session on a seeded account
  means somebody has signed in with the shared password. Deleting ends it.

Deleting an account does **not** touch the rows it owns: the row ACLs name
`user:<uuid>`, the uuid comes from Postgres, and re-creating with the same
`userId` restores the match exactly. What it destroys is that account's
sessions, labels and team memberships — the seeder re-creates the labels and
memberships in the same run, and there are no sessions worth keeping before the
app ships. **After** the app ships this becomes expensive: every signed-in user
is logged out, and any push target registered against the old account is gone.

Where there is no hash column at all — a Supabase export that dropped
`encrypted_password` — the seeder exits `2` before creating anything rather than
making 650 passwordless accounts and reporting success.

### 5.2 Provision the collections, then seed

```bash
cd docs/appwrite-spike/migrate
npm install                      # once; pg is not declared anywhere else

export AW_ENDPOINT="https://fra.cloud.appwrite.io/v1"
export AW_PROJECT="6ac51e70002ab6238fec"
# AW_KEY and PG_URL already exported in section 2. No password: see 5.1.

node seed-identities.mjs         # users, ward teams, role labels — ALWAYS FIRST
```

The schema comes from `infra/appwrite/provision.mjs`, run from the repo root as
in Phase 0 — not from a script in this directory. `prep.mjs` used to create the
spike's own snake_case collections and has been deleted: nothing writes to that
shape any more, so running it would have provisioned a second wrong schema beside
the real one.

Every script prints the endpoint and project it resolved, on stderr, before it
does anything. **Read that line.** The reason it is there: until recently
`prep.mjs` (now deleted), `seed-identities.mjs` and `reconcile.mjs` had
`http://localhost:8080/v1` baked in and read their credentials from a path that
does not exist in this repository, so they ignored `AW_ENDPOINT`, `AW_PROJECT`
and `AW_KEY` entirely — and Appwrite answers a misdirected or unpermitted read
with `200 {"total": 0}` rather than an error, so a run against the wrong project
does not fail, it reports that there was nothing to do.

For the full planned schema — indexes, column widths, the two buckets — use
`infra/appwrite/provision.mjs` and confirm with `infra/appwrite/verify.mjs`, as
in Phase 0. Both are idempotent.

### What Identity Seeding Executes:
1. **Ward Teams:** Creates an Appwrite Team for every distinct ward present in `profiles` and `reports`. Team ID format: `wardTeam(state, lga, ward)`.
2. **Appwrite Users:** Creates an Appwrite Auth user for each `profiles` row
   joined with `auth.users`, preserving the Postgres `id` as `userId`, and
   importing that account's own bcrypt hash where it has one — see 5.1 for the
   three cases and for why a 409 is not an import.
3. **Role Labels:** Assigns Appwrite alphanumeric user labels (`admin`,
   `ldpCoordinator`, `projectStaff`, `ewv`, `ewr`, `ewm`) from
   **`effectiveRole(profile)`**, not from `profiles.role` — see "The escalation
   this gate was built to catch" in Phase 4. An unapproved or disabled account
   gets no label, which is what Postgres does.
4. **Ward Team Memberships:** Enrolls Early Warning Monitors (`ewm`) into their
   ward teams, under the same `effectiveRole` condition.

### Validation
Confirm the script exits with code `0` and that the `failures` array in its JSON
summary is empty. Resolve anything in `failures` before proceeding to document
migration: an ACL naming a user, label or team that was never created is
accepted in silence and grants nobody anything.

Then read the `passwords` block, which is not covered by the exit code alone:

- `imported` should be the bcrypt count from 3.3's source audit.
- `none` should be the OAuth-only and magic-link-only count from the same audit.
- `notBcrypt` should be `0`; each one is named in `failures`.
- `alreadyExisted` should be `0` on a first run. **Anything else means those
  accounts kept an older password and this run did not change it** — go back to
  5.1. A 409 made this script safe to re-run for teams, labels and memberships,
  and it has never made the password safe to re-run.

---

## 6. Phase 3: Data Migration Sequence

One script, nine collections, from the same directory and the same exported
environment as Phase 2:

```bash
node copy-tables.mjs
```

It is idempotent: every row keeps its Postgres primary key as its Appwrite `$id`,
so a re-run answers 409 rather than duplicating.

### Order, and why it is not a preference

`profiles` → `reports` → `verifications`, then the other six in any order. A
report's ACL names the ward team its author belongs to, and a verification's
names the team of the report it votes on, so each of the first three needs the
one before it read first. `copy-tables.mjs` holds that order in `TABLES`; it is
not something the operator sequences by hand.

1. **`profiles`** — `read("user:<id>")`, `read("team:<ward>")`, and read for
   `admin`, `ldpCoordinator`, `projectStaff`, `ewv`, `ewr`.
2. **`reports`** — `read("user:<owner>")`, `read("team:<ward>")`, and read for
   the six labels in `STAFF_ROLES`. This is the one that reproduces
   `reports_select`, and the reason Phase 4 exists.
3. **`verifications`** — `read("user:<verifier>")`, `read("team:<report's
   ward>")`, and the same staff labels. A vote on a report that did not migrate
   is **skipped**, not written: its ACL would name a ward derived from nothing.
4. **`alerts`**, **`authorities`**, **`app_settings`**,
   **`scheduled_escalations`**, **`knowledge_base`**, **`news_links`** — the six
   that had nothing writing them at all. Their ACLs come from `policy.js`'s
   `RULES`, and five of the six are in fact read from **table-level**
   permissions: `plan.mjs` leaves row security off for them, so the row's ACL is
   stored and inert. It is written anyway, so a migrated row and one the `client`
   Function creates later are indistinguishable, and so switching row security on
   later does not silently empty the table.

There is no `label:fieldAgent` anywhere in this system; that name appeared only
in an earlier version of this list.

### What it writes into, and what it refuses to lose

The schema is read from **`plan.mjs`'s `COLLECTIONS`** — what
`infra/appwrite/provision.mjs` actually creates — and not from `columns.json`.
That file is derived from the migrations alone, and the plan adds the
denormalised columns Appwrite needs and Postgres never had: `reports.userName`
and `userRole`, `verifications.verifierName`, `state`, `lga`, `ward`. Reading the
narrower file is what made those look unplanned, and is why this phase was
believed to need a `plan.mjs` change first. **It does not.**

Those Appwrite-only values come from the same expressions `write.js` uses —
the author's profile for a report, `stampReportLocation` for a verification — so
a migrated row carries what a new one would. `reports.previousStatus` is
deliberately left unset: it exists so an event Function can tell a status change
from any other edit, and stamping a migrated row's current status would announce
a change that never happened.

Everything else is imported rather than restated: the camelCase rule is
`extract-schema.mjs`'s own `toField`, and the ACLs are the functions the
migration and the Function already use. None of them can drift from what
`verify.mjs` holds the project to.

*Criteria:* every table reports `failed: 0`, and `unplannedColumns` is empty. A
Postgres column with no planned column has nowhere to go, so it is reported
rather than dropped in silence — add it to the migrations and re-run
`extract-schema.mjs`, or accept the loss knowingly. A value longer than its
column fails rather than being truncated.

### Storage Asset Migration: `copy-storage.mjs`

```bash
SUPABASE_URL="https://<ref>.supabase.co" \
STORAGE_MAP=storage-map.json \
node copy-storage.mjs
```

The buckets are `report-images` and `profile-images` — there is no `avatars`
bucket; `plan.mjs` provisions those two names and both clients read them.

**The file id is not ours to choose.** The Flutter client derives it from the
storage path when it renders an image (`AppwriteDataBackend.fileIdFor`) and
nothing persists the mapping — the comment in that file is blunt about why: "a
digest of the path, and a digest cannot be inverted". A file copied under any
other id is unreachable, the request 404s, and the only symptom is an image that
does not load. `storage-ids.mjs` is a port of that function, pinned by
`storage-ids.test.mjs` against the cases the Dart suite asserts.

Two different paths colliding on one id **stops the run** before anything is
uploaded, because the second upload would replace the first user's evidence with
no error anywhere.

It then rewrites the Supabase URLs still on migrated rows — `reports.imageUrls`,
`profiles.profileImageUrl`, `knowledge_base.imageUrl`. `news_links.url` is
deliberately left alone: it links to someone else's article, not a file of ours.
All three carry across now. They did not before: `migrate.mjs` wrote neither
image column, so every photograph in the system was being lost — silently, since
"0 of 3 rewritten" reads like there was nothing to do. The run therefore
distinguishes three cases by name: the table is **not migrated yet**, it has **no
rows yet**, or the column is **ABSENT on all N rows** — the last meaning whatever
migrated that table does not carry it, which is the one that loses data.

*Criteria:* `failed: 0` per bucket, the gate's bucket table showing `missing 0`,
and no column reported ABSENT. Idempotent — the id is a function of the path, so
a re-run answers 409 and uploads nothing; the rewrite is idempotent because an
Appwrite URL no longer matches the Supabase pattern it looks for. `STORAGE_MAP`
writes the path -> id mapping as JSON.

Run it **after** `copy-tables.mjs`: the rewrite edits rows, so the rows have to
be there.

Both buckets are `public: true` in Supabase and `read("any")` in Appwrite, so
the bytes are reachable by everyone in both. One widening, recorded here rather
than fixed: Supabase's RLS on `storage.objects` let a user list only their own
folder, while an Appwrite bucket readable by `any` can be listed by anyone. That
exposes which files exist, not their contents, since the contents were already
public in both.

> ### A migrated row is readable by more roles than a new one
>
> The one thing left to decide about this phase, and it is a product question.
>
> `copy-tables.mjs` stamps `migrate.mjs`'s permissions on the three collections
> with row security on, because those were written to reproduce the RLS policy
> each row was protected by — and Phase 4 confirms they do. The `client`
> Function stamps `policy.js`'s `RULES` on a row created *after* the cutover,
> and that is a **narrower** set:
>
> | | migrated row also grants | new row does not |
> |---|---|---|
> | `profiles` | ward team, `ldpCoordinator`, `projectStaff`, `ewv`, `ewr` | — |
> | `reports` | `ldpCoordinator`, `projectStaff`, `techSupport` | — |
> | `verifications` | the verifier themselves, `ldpCoordinator`, `projectStaff`, `techSupport` | — |
>
> Narrowing access during a cutover is not the migration's call, so migrated
> rows match Postgres and the difference is written down rather than split.
> `copy-tables.test.mjs` pins it, so changing either side fails until the new
> difference is written down too.
>
> Part of it looks deliberate: `profiles` is narrow because the fields a
> reviewer needs — `userName`, `reporterName`, `verifierName` — are denormalised
> onto the rows that reference them, so no cross-profile read is needed. Part
> looks like an oversight: `ldpCoordinator` and `projectStaff` are in `DECIDERS`
> and may approve, reject and reopen a report, and `RULES.reports` does not let
> them read one. The admin panel is unaffected either way — it reads through the
> Function with an API key, which bypasses ACLs — so the symptom would be a
> coordinator seeing an empty list in the Flutter app.

---

## 7. Phase 4: Reconciliation Gate

**MANDATORY CHECKPOINT:** Do NOT switch production traffic if this step fails.

Execute the visibility reconciler, from `docs/appwrite-spike/migrate` with the
same environment as Phase 2:
```bash
node reconcile.mjs
```

### What `reconcile.mjs` Proves:
- **Every table a signed-in user can read, for every user** — 15 of them, not a
  sample of either. It queries Postgres with RLS active as that user
  (`request.jwt.claim.sub` + `set role authenticated`), opens a real Appwrite
  session as that user, lists what the session can see, and diffs the **ids**.
  Comparing ids rather than field values is what lets it be correct about a
  project whose column names it does not know.
- **It does not know anybody's password, and does not need one.** Since 5.1
  imports the hashes, there is no shared secret to sign in with: the gate mints a
  session instead — `POST /users/{userId}/tokens` with `AW_KEY` returns a secret,
  and `POST /account/sessions/token` exchanges it for a session cookie. `AW_KEY`
  authorises that minting and nothing else; every row read still goes through the
  user's own session, which is the property the whole gate rests on. A key-based
  read would answer "fine" for every table however the permissions were stamped.
  A token that comes back with an empty `secret` means the key was not sent, and
  the gate says so rather than reading it as "this user sees nothing".
- It reads the **effective** policy from `pg_policies` and quotes it on every
  finding. Not from `supabase/deploy/schema.sql`: that file is a concatenation
  in which later migrations redefine policies, and its first `profiles_select`
  is not the one installed.
- It checks the **storage buckets** by presence: every Supabase object must be
  in Appwrite under the id the app derives from its path. A missing file fails
  the run.
- It **polices its own coverage**. Any table with an `authenticated` SELECT or
  ALL policy that is neither reconciled nor listed as deliberately out of scope
  fails the run with exit `2`. The previous version compared `reports` alone and
  called the result "100% per-user visibility parity"; a list maintained by hand
  drifts, a list that fails the run when it drifts does not.
- **A refused table is reported as refused, never as zero rows.** A 401 or 403
  on a listing means the table's own permissions do not admit that session, so
  the read never happened. That is narrower than any RLS grant and therefore
  never a leak — but it is not "this user sees nothing" either, and the summary
  gives it a `denied` column of its own. The distinction is the only thing that
  can speak for an **empty** table: seven of the fifteen hold no rows at cutover,
  and a 401 read as `[]` matches Postgres's zero rows exactly, so a table nobody
  could open would pass as clean right up to the day it filled up. Where every
  session is denied a table that is not declared narrower on purpose, the run
  fails and names what `plan.mjs` grants.
- **Rows the copier declined are forgiven by name, not by filter.** `NOT_COPIED`
  in `reconcile.mjs` mirrors each `skip` in `copy-tables.mjs` — the legacy
  reports with no LGA, and the verifications attached to them — with a predicate
  and a reason. Those rows stay in the Postgres side of the diff, are counted,
  and are printed with their ids; they are simply not counted as losses.
  Excluding them from the query instead would pass just as quietly while making
  the gate unable to tell a declared skip from a production row that failed to
  migrate, which is the one thing it is for.
- **Fail Criteria:** exits `1` if any user sees more rows (permission leak) or
  fewer (data loss), if a session cannot be minted, if a table holds rows in
  Postgres that no user can read in Appwrite, or if a table refuses every
  session without a declaration saying it should. It pages the listing and
  throws on a non-2xx rather than reading an error as an empty result — an
  earlier version did the latter and confidently reported a total migration
  failure for a correct migration.
- **Exit `2` is a configuration problem, not a verdict:** unreachable endpoint,
  a missing `AW_KEY`, an uncovered table. Nothing was compared. A run that never
  reached Appwrite must never read as a list of per-account problems, so it stops
  at the first transport error rather than producing one finding per user.
- **Success Criteria:** exits `0` — every user identical in every table, and
  every stored file present. The closing line names which of the two it checked:
  without `AW_KEY` the storage half is skipped and says so.

With `AW_KEY` set it also prints each table's total row count, read with the
key. That number is **diagnosis only and never part of a verdict** — a key reads
past the ACLs that are the subject of the comparison. It exists to tell "nothing
migrated this table" from "everything migrated and every ACL grants nobody",
which look identical from a user session and need opposite fixes.

Narrow a failure with `RECONCILE_TABLES=profiles,reports`. Point it at the
spike's pre-1.8 stack with `AW_ROWS_API=documents`; the default is TablesDB,
which is what the app and the Functions use.

### What it does NOT prove
- **Storage beyond presence.** The gate checks that every Supabase object is in
  Appwrite under the id the app will ask for, and nothing else. It does not
  compare bytes or checksums, and it does not diff per user — both systems serve
  these buckets to everyone, so that would be the same answer six times. It
  needs `AW_KEY`, because listing a bucket is an admin read and presence is not
  a question about ACLs.
- **That Appwrite evaluates ACLs the way the test harness does.** `npm test` in
  `docs/appwrite-spike/migrate` runs the gate — and `copy-tables.mjs` — against
  a stand-in that implements the documented REST contract and decides visibility
  the way Appwrite does: the table's own permissions, and a row's ACL only where
  `plan.mjs` switches row security on. It reads that from `plan.mjs` and
  evaluates the permission strings `migrate.mjs` and `policy.js` actually stamp
  against the labels `accountLabels` actually assigns — all imported, none
  restated. That pins the gate's logic and catches ACL *design* errors: it found
  the label escalation below, and that five of these six tables are served from a
  table rule rather than the row ACLs. Only a run against a real project proves
  Appwrite agrees, and that run is this phase.

### Two tables are narrower than the RLS, on purpose

Phase 4 accepts a **loss** on `authorities` and `scheduled_escalations`, says so
out loud on every run, and still fails on any **leak** anywhere. No declaration
forgives a user seeing a row Postgres would not have shown them.

- **`authorities`** — `plan.mjs` grants `read("label:admin")`; Postgres granted
  all of `is_staff()`. The only consumer is the admin panel, and
  `CRADI-Mobile-Admin/lib/appwrite-server.ts` gates that to an approved,
  non-disabled **admin**, so no other staff role ever read this table.
- **`scheduled_escalations`** — `plan.mjs` grants nobody; Postgres granted
  `ldp_coordinator`, `project_staff` and `admin`. The worker cron writes and
  reads it with an API key; no client queries it.

A declared narrowing never hides an unmigrated table: with `AW_KEY` set, a table
holding **zero** rows is reported as empty regardless, because "nobody may read
this" and "there is nothing to read" are indistinguishable from a session and
only one of them is acceptable.

Three tables go slightly **wider**: `alerts`, `knowledge_base` and `news_links`
are `read("any")`, which includes a guest, where Postgres required a session.
The gate compares signed-in users, so it does not report this. It is public
reference content, and the decision is recorded here rather than in a diff.

### The escalation this gate was built to catch
Appwrite labels used to be assigned from `profiles.role` alone. Every RLS policy
branches on `app_role()`, which returns `'user'` unless the account
**is_approved and not is_disabled** — so an unapproved or disabled staff account
arrived holding the reach its column claimed (every profile, every report, every
verification) where Postgres had shown it its own row and nothing else. No ACL
anywhere names `label:approved` alongside the role, so the role label alone was
enough.

This was **not only in the migration**: `accountLabels()` in
`functions/cradi/src/lib/policy.js` is what `write.js` calls on every change to
`role`, `isApproved` or `isDisabled`, and it had the same rule and no tests. It
now withholds the role label until the account is approved, and
`seed-identities.mjs` calls it rather than keeping a second copy — so a migrated
account starts with exactly what a later profile edit would give it, including
the `approved` label that `plan.mjs` requires for `messages` and that the seeder
never used to set.

**This changes running behaviour.** An account whose approval is revoked now
loses its role label as well as `approved`; approving it again restores both,
since `syncLabels` re-runs on any of those three fields. The test that pinned
the old behaviour (`drops 'approved' when approval is revoked`, which asserted
the role label survived) is updated, with the reasoning in place. A gate finding
caused by this marks `demotedRole: true`.

---

## 8. Phase 5: Production Traffic Cutover

Once Phase 4 passes:

### 8.1 Admin Portal Cutover (`CRADI-Mobile-Admin`)
1. In Vercel / hosting provider, update environment variables for production:
   ```env
   NEXT_PUBLIC_APPWRITE_ENDPOINT=https://fra.cloud.appwrite.io/v1
   NEXT_PUBLIC_APPWRITE_PROJECT_ID=6ac51e70002ab6238fec
   APPWRITE_API_KEY=<PRODUCTION_API_KEY>
   # The rest already default to these values in lib/appwrite.ts and
   # lib/constants.ts — set them only to override:
   #   NEXT_PUBLIC_APPWRITE_DATABASE_ID=cradi
   #   NEXT_PUBLIC_APPWRITE_FN_CLIENT=client
   #   NEXT_PUBLIC_APPWRITE_REPORT_IMAGES_BUCKET=report-images
   ```
   There is no `NEXT_PUBLIC_APPWRITE_BUCKET_ID`: the admin reads
   `NEXT_PUBLIC_APPWRITE_REPORT_IMAGES_BUCKET`, and it must agree with the
   Flutter client's `REPORT_IMAGES_BUCKET` define. The database is `cradi`, not
   the previous project's `6941e2c2003705bb5a25`.
2. Deploy the latest `main` commit of `CRADI-Mobile-Admin`.
3. Disable `NEXT_PUBLIC_MAINTENANCE_MODE`.
4. Log into the admin portal using an administrator account.
5. Verify:
   - Dashboard stats load and match migrated counts.
   - Live report list loads with images rendering.
   - Authority contacts can be edited.
   - Broadcast alert test draft works.

### 8.2 Mobile Client Release
1. Create and push a release tag on `KusuConsult-NG/CRADI-mobile`:
   ```bash
   git tag v2.0.0
   git push origin v2.0.0
   ```
2. GitHub Actions CI automatically triggers `build-android-release`:
   - Checks secret guard for `KusuConsult-NG/CRADI-mobile`.
   - Validates `APPWRITE_ENDPOINT` and `APPWRITE_PROJECT_ID` in `env.json`.
   - Builds signed release APK / AAB.
3. Publish update to Google Play Store & Apple TestFlight / App Store.

### 8.3 Cutover Transitions Handling
- **Password Reset & Auth Links:** Users clicking legacy Supabase password recovery links will be seamlessly routed to `/forgot-password?expired=1` with an in-app notice prompting them to request a fresh reset link via Appwrite.
- **Push Notification Transition:** As handsets update to the Appwrite release,
  the app registers the device's FCM/APNs token as an Appwrite push target. The
  `worker` Function then reconciles that target's topic subscriptions
  (`all-users`, `state-<slug>`, `lga-<state>-<lga>`) from the user's `profiles`
  row — on every profile write, and again whenever the client asks via
  `sync_push_subscriptions`. Nothing client-side subscribes to topics.
- **The gap this leaves, stated plainly:** a handset that has not yet updated is
  reachable by neither stack. The old build talked to OneSignal, which no build
  now contains; the new one talks to Appwrite, which the old build cannot reach.
  Phase 3's dual-send mitigation went with the OneSignal client. So between the
  cutover and a user updating, **push does not reach them at all** — and there
  is no server-side way to shorten that window.
- **Emergency Resilience:** SMS is therefore the channel that actually spans the
  cutover, and the only one. Critical hazard notifications reach local
  authorities and registered coordinators by Termii regardless of app version.
  Confirm before the window that the Termii balance covers the expected volume
  for the whole update period, not just the cutover day, and that the phone
  numbers passed Phase 0's `+234` format audit — an unnormalised number is
  rejected by Termii, and that rejection is the one failure here with no
  fallback behind it.

---

## 9. Phase 6: Post-Cutover Monitoring & Verification

Monitor the production environment for 48 hours post-cutover:

1. **Appwrite Functions Executions:**
   - Go to **Appwrite Cloud Console** -> **Functions** -> `worker` & `client`.
   - Monitor Execution Logs for runtime errors, out-of-memory errors, or timeouts (over 15s).
2. **Termii SMS Gateway:**
   - Check Termii balance and delivery receipts. Verify status code `200` and `message_id` on new alert broadcasts.
3. **Appwrite Storage:**
   - Verify newly submitted incident images upload correctly and display in the Admin panel.
4. **Offline Mobile Sync:**
   - Verify newly submitted field reports from mobile sync successfully when devices reconnect.

---

## 10. Phase 7: Rollback Strategy

If a critical, blocking flaw is discovered during the cutover window:

### Scenario A: Flaw Discovered Before Mobile Release (During Migration / Admin Cutover)
1. **Abort:** Cancel the cutover.
2. **Re-enable Supabase Writes** — the inverse of the `REVOKE` in 4.3:
   ```sql
   GRANT INSERT, UPDATE, DELETE ON
     public.reports, public.verifications, public.profiles,
     public.alerts, public.authorities, public.app_settings
   TO authenticated;
   ```
   Then re-run 4.3's verification insert and confirm it now **succeeds**. Note
   that this grants to `authenticated` only: `anon` had no write grants to
   restore, and handing it any would be a worse outcome than the failed
   cutover. If your project's grants differed, restore from the snapshot you
   took rather than from this block:
   ```sql
   -- Take this BEFORE 4.3, and keep it in the execution log.
   SELECT grantee, table_name, privilege_type
   FROM information_schema.role_table_grants
   WHERE table_schema = 'public' AND grantee IN ('anon', 'authenticated')
     AND privilege_type IN ('INSERT', 'UPDATE', 'DELETE')
   ORDER BY grantee, table_name, privilege_type;
   ```
3. **Revert Admin Portal:** Redeploy previous admin release pointing to Supabase.
4. **Communicate:** Notify team that maintenance is complete on the existing stack.

### Scenario B: Flaw Discovered After Mobile Release
Because mobile apps cannot be instantly rolled back across client handsets once published:
1. **Fix Forward Priority:** The Appwrite Function backend is serverless. Function hotfixes can be deployed to Appwrite Cloud in seconds without client app updates.
2. **Hotfix Command:**
   ```bash
   node infra/appwrite/local/deploy.mjs
   ```
3. **Database Hotfix:** Attributes and permissions can be adjusted dynamically in Appwrite Cloud Console or via `provision.mjs`.
4. If full database recovery is required: export delta records submitted to Appwrite Cloud (`$createdAt > cutover_start`) and backport to Supabase Postgres before falling back.
