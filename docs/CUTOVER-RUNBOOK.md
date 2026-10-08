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
export MIGRATION_PASSWORD="<SHARED_SEED_PASSWORD>"   # Read 5.1 before choosing this

# Consumed by the worker Function, set in the Appwrite console, not here
export TERMII_API_KEY="<TERMII_API_KEY>"
export TERMII_SENDER_ID="CRADI"
```

Do **not** export `APPWRITE_BUCKET_ID`. `verify.mjs` treats it as a signal that
the project is on a one-bucket tier; with it set, the verifier checks a
single-bucket plan and can report that the project matches while neither planned
bucket exists. It prints a note when it sees the variable — heed it.

The database is `cradi`. Nothing reads an `AW_DATABASE_ID`: the migration scripts
hardcode `/databases/cradi/`, and the tooling under `infra/appwrite` reads
`APPWRITE_DATABASE_ID`, defaulting to `cradi`. `6941e2c2003705bb5a25` was the
*previous* Cloud project's database — set nothing and leave it behind.

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
From the repository root, with the `APPWRITE_*` exports from section 2 in place.

Run the cloud schema and plan verifier:
```bash
node infra/appwrite/verify.mjs
```
*Criteria:* no differences against `plan.mjs`. Unplanned extras are listed
without failing the run, so read the output rather than only the exit code.

Run the automated probe and health check:
```bash
node infra/appwrite/cloud-check.mjs
```
*Criteria:* 8/8 checks pass, temporary test documents cleaned up.

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

### 5.1 Decide what happens to everyone's password — before you run anything

`seed-identities.mjs` does **not** carry Supabase password hashes across. It
creates each account with one shared `MIGRATION_PASSWORD`, so after it runs, no
user's own password works. That is fine for a rehearsal and wrong for
production, and it is a product decision, not a scripting one. Two ways out:

- **Import the hashes (preserves every user's password).** Supabase keeps bcrypt
  in `auth.users.encrypted_password`, and Appwrite accepts a pre-hashed bcrypt
  password on `POST /users/bcrypt` (`createBcryptUser` in the server SDKs),
  taking `userId`, `email`, `password` and `name`. Users with a null or empty
  `encrypted_password` — OAuth-only and magic-link-only accounts — have no hash
  to import and need the plain `POST /users` path or none at all.
  **This is not implemented in `seed-identities.mjs`, and nothing in this
  repository has exercised it against Cloud.** Treat it as the change to make
  and verify, not as a step to follow.
  It also breaks Phase 4 as written: `reconcile.mjs` signs in as each user with
  `MIGRATION_PASSWORD`, which it would no longer know. A password-free session
  (`POST /users/{userId}/tokens`, exchanged via `PUT /account/sessions/token`)
  is the shape of the answer, and is likewise unimplemented and untested here.
- **Force a reset for everyone.** Run the seeder as it stands, then require a
  password reset on first sign-in and say so in the Phase 1 broadcast. Phase
  5.3's expired-link handling already catches users who click an old Supabase
  reset mail, so the path exists. Budget for the support load: ~650 accounts.

`MIGRATION_PASSWORD` has no default and must be at least 8 characters. Both
`seed-identities.mjs` and `reconcile.mjs` read it and they must agree. It is a
shared secret across every seeded account for as long as it is in force — keep
the window short, and never commit it.

### 5.2 Provision the collections, then seed

```bash
cd docs/appwrite-spike/migrate
npm install                      # once; pg is not declared anywhere else

export AW_ENDPOINT="https://fra.cloud.appwrite.io/v1"
export AW_PROJECT="6ac51e70002ab6238fec"
# AW_KEY, PG_URL, MIGRATION_PASSWORD already exported in section 2.

node prep.mjs                    # collections and attributes
node seed-identities.mjs         # users, ward teams, role labels — ALWAYS FIRST
```

Every script prints the endpoint and project it resolved, on stderr, before it
does anything. **Read that line.** The reason it is there: until recently
`prep.mjs`, `seed-identities.mjs` and `reconcile.mjs` had
`http://localhost:8080/v1` baked in and read their credentials from a path that
does not exist in this repository, so they ignored `AW_ENDPOINT`, `AW_PROJECT`
and `AW_KEY` entirely — and Appwrite answers a misdirected or unpermitted read
with `200 {"total": 0}` rather than an error, so a run against the wrong project
does not fail, it reports that there was nothing to do.

If `prep.mjs` is redundant because the schema already exists, it is harmless:
every create answers 409 on a second run. For the full planned schema — indexes,
column widths, the two buckets — use `infra/appwrite/provision.mjs` and confirm
with `infra/appwrite/verify.mjs`, as in Phase 0.

### What Identity Seeding Executes:
1. **Ward Teams:** Creates an Appwrite Team for every distinct ward present in `profiles` and `reports`. Team ID format: `wardTeam(state, lga, ward)`.
2. **Appwrite Users:** Creates an Appwrite Auth user for each `profiles` row joined with `auth.users`, preserving the Postgres `id` as `userId`.
3. **Role Labels:** Assigns Appwrite alphanumeric user labels (`admin`, `ldpCoordinator`, `projectStaff`, `fieldAgent`, `ewm`, etc.) corresponding to `profiles.role`.
4. **Ward Team Memberships:** Automatically enrolls Early Warning Monitors (`ewm`) into their respective ward teams.

### Validation
Confirm the script exits with code `0` and that the `failures` array in its JSON
summary is empty. A 409 on `/users` is *not* a failure — it means the account
already exists, which is what makes the script safe to re-run; the script counts
those separately and only reports real errors. Resolve anything in `failures`
before proceeding to document migration: an ACL naming a user, label or team
that was never created is accepted in silence and grants nobody anything.

---

## 6. Phase 3: Data Migration Sequence

Run the migrator, from the same directory and the same exported environment as
Phase 2:
```bash
node migrate.mjs
```

It is idempotent: every document keeps its Postgres UUID as its Appwrite id, so
a re-run collides with 409 rather than duplicating.

### Ordered Collections:
1. **`profiles`:** Stamped with read/write permissions for `user:<userId>`.
2. **`authorities`:** Public read permissions, admin-only write.
3. **`app_settings`:** Read permission for all authenticated users, admin write.
4. **`reports`:** Stamped with write-time ACLs:
   - Creator user: `user:<userId>` (read + update)
   - Ward team: `team:<wardTeam>` (read)
   - Response roles: `label:admin`, `label:ldpCoordinator`, `label:fieldAgent` (read + update)
5. **`verifications`:** Linked by report ID, stamped with voter user and admin ACLs.
6. **`alerts`:** Broadcaster user and role-targeted broadcast ACLs.

### Storage Asset Migration
Transfer storage assets from Supabase Storage S3 buckets to Appwrite Cloud Storage:
1. Bucket `report-images`: Transfer all incident image attachments. Set read permission to `Any` (public viewable for incident reports).
2. Bucket `avatars`: Transfer user avatars. Set read permission to `Any`, write permission to `user:<userId>`.

Validate file counts and checksums against the Supabase bucket contents.

---

## 7. Phase 4: Reconciliation Gate

**MANDATORY CHECKPOINT:** Do NOT switch production traffic if this step fails.

Execute the visibility reconciler, from `docs/appwrite-spike/migrate` with the
same environment as Phase 2:
```bash
node reconcile.mjs
```

### What `reconcile.mjs` Proves:
- For **every row in `profiles`**, not a sample: it queries Postgres with RLS
  active as that user (`request.jwt.claim.sub` + `set role authenticated`),
  signs in to Appwrite as that user with `MIGRATION_PASSWORD`, lists what the
  session can see, and diffs the document ids.
- **Fail Criteria:** exits `1` if any user sees more documents (permission leak)
  or fewer (data loss), or if the sign-in fails. It pages the Appwrite list and
  throws on a non-2xx rather than reading an error as an empty result — an
  earlier version did the latter and confidently reported a total migration
  failure for a correct migration.
- **Success Criteria:** exits `0`, every user identical.

### What it does NOT prove
It compares the **`reports` collection only** — the one whose RLS was hardest,
and the reason the gate exists. It says nothing about `profiles`,
`authorities`, `app_settings`, `verifications`, `alerts`, or storage buckets.
Treat a green run as "the hard case is right", not as visibility parity across
the migration. Extending it to the other collections, and to file-level bucket
permissions, is the work that would make this gate mean what Phase 4's heading
claims. Until then, check the remaining collections by hand against the
baseline counts from 4.4 and spot-check at least one document per role.

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
