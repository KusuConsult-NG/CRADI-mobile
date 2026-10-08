# Production Cutover Runbook: Supabase → Appwrite Cloud

**Target System:** Appwrite Cloud (`fra.cloud.appwrite.io`)  
**Project ID:** `6ac51e70002ab6238fec`  
**Database ID:** `6941e2c2003705bb5a25`  
**Region:** Frankfurt (`fra`)  
**SMS Gateway:** Termii Nigeria (`generic` route)  
**Push Providers:** Firebase Cloud Messaging (`fcm`), Apple Push Notification service (`apns`)  
**Functions:** `client` (user operations), `worker` (triggers & SMS outbox drain)  

---

## 1. Cutover Architecture & Strategy

This runbook specifies the end-to-end, deterministic procedure for executing the production cutover from Supabase (Postgres RLS, Supabase Auth, Storage) and OneSignal to Appwrite Cloud and Appwrite Messaging.

### Core Architecture Invariants
1. **Identities Before Documents:** Document ACLs in Appwrite reference users (`user:<uuid>`), role labels (`label:<role>`), and ward teams (`team:<teamId>`). In Appwrite, an ACL referencing an uncreated team or label is silently accepted without granting access to anyone. Therefore, identity seeding MUST run before document migration.
2. **Postgres UUID Preservation:** User IDs and document IDs preserve Postgres 36-character UUID strings verbatim (`p.id` $\to$ `userId`, `docId`). No stripped dashes, no translation layers.
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
```bash
export AW_ENDPOINT="https://fra.cloud.appwrite.io/v1"
export AW_PROJECT="6ac51e70002ab6238fec"
export AW_KEY="<APPWRITE_SERVER_API_KEY>"          # Requires full database, users, teams, functions, and storage scopes
export AW_DATABASE_ID="6941e2c2003705bb5a25"
export PG_URL="<SUPABASE_POSTGRES_DIRECT_URL>"     # Direct connection (port 5432 or 6543)
export TERMII_API_KEY="<TERMII_API_KEY>"
export TERMII_SENDER_ID="CRADI"
```

Verify the local environment has Node.js $\ge 22$, PostgreSQL client tools (`psql`), and Flutter $\ge 3.24$.

---

## 3. Phase 0: Pre-Flight Audit & Infrastructure Verification

Execute these pre-flight checks at least 24 hours prior to the scheduled cutover window.

### 3.1 Appwrite Cloud Infrastructure Check
Run the cloud schema and plan verifier:
```bash
node infra/appwrite/verify.mjs
```
*Criteria:* Must report `0` differences against `plan.mjs`.

Run the automated probe and health check:
```bash
node infra/appwrite/cloud-check.mjs
```
*Criteria:* 8/8 checks pass, temporary test documents successfully cleaned up.

### 3.2 Push Providers Status in Appwrite Console
Navigate to **Appwrite Cloud Console** $\to$ **Project Settings** $\to$ **Messaging**:
1. **FCM Provider (`fcm`):** Verify status is **Enabled**. Confirm service account JSON corresponds to Firebase project `cradi-mobile`.
2. **APNs Provider (`apns`):** Verify status is **Enabled** (or ready with Apple developer team key `.p8`, Key ID, and Team ID).
3. Test topic registration:
   ```bash
   node infra/appwrite/push-smoke-test.mjs
   ```
   *Criteria:* Target registration and topic reconciliation pass.

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
- Ward teams: verify the `wardTeam(state, lga, ward)` slugifier in `functions/cradi/src/lib/appwrite.js` handles lengths $> 36$ characters using hashing/truncation (already verified across all 584 Nigerian pilot wards).

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
Lock all public writes on Supabase while keeping read access available for the migrator:
```sql
-- Apply temporary write lock policy
ALTER TABLE reports ENABLE ROW LEVEL SECURITY;
CREATE POLICY freeze_reports_write ON reports FOR INSERT WITH CHECK (false);
CREATE POLICY freeze_reports_update ON reports FOR UPDATE USING (false);
CREATE POLICY freeze_reports_delete ON reports FOR DELETE USING (false);

CREATE POLICY freeze_verifications_write ON verifications FOR INSERT WITH CHECK (false);
CREATE POLICY freeze_profiles_write ON profiles FOR UPDATE USING (false);
CREATE POLICY freeze_alerts_write ON alerts FOR INSERT WITH CHECK (false);
```

### 4.4 Drain Queues & Record Baseline Row Counts
Ensure no background tasks are in-flight:
```sql
-- Verify SMS outbox is drained
SELECT status, count(*) FROM sms_queue GROUP BY status;
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

Run `seed-identities.mjs` against Appwrite Cloud.

```bash
cd docs/appwrite-spike/migrate
AW_ENDPOINT="https://fra.cloud.appwrite.io/v1" \
AW_PROJECT="6ac51e70002ab6238fec" \
AW_KEY="$AW_KEY" \
PG_URL="$PG_URL" \
node seed-identities.mjs
```

### What Identity Seeding Executes:
1. **Ward Teams:** Creates an Appwrite Team for every distinct ward present in `profiles` and `reports`. Team ID format: `wardTeam(state, lga, ward)`.
2. **Appwrite Users:** Creates an Appwrite Auth user for each `profiles` row joined with `auth.users`, preserving the Postgres `id` as `userId`.
3. **Role Labels:** Assigns Appwrite alphanumeric user labels (`admin`, `ldpCoordinator`, `projectStaff`, `fieldAgent`, `ewm`, etc.) corresponding to `profiles.role`.
4. **Ward Team Memberships:** Automatically enrolls Early Warning Monitors (`ewm`) into their respective ward teams.

### Validation
Confirm the script exits with code `0`. If any 409 collisions or errors occur, resolve immediately before proceeding to document migration.

---

## 6. Phase 3: Data Migration Sequence

Run the collection migrators in strict dependency order:
```bash
AW_ENDPOINT="https://fra.cloud.appwrite.io/v1" \
AW_PROJECT="6ac51e70002ab6238fec" \
AW_KEY="$AW_KEY" \
PG_URL="$PG_URL" \
node migrate.mjs
```

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

Execute the visibility reconciler:
```bash
node reconcile.mjs
```

### What `reconcile.mjs` Proves:
- For each test user profile (admin, field agent, EWM monitor, normal citizen):
  - Queries Supabase Postgres with RLS active as that user's JWT.
  - Queries Appwrite Cloud with a real authenticated session for that user.
  - Diffing the document IDs visible to both systems.
- **Fail Criteria:** Exits `1` if any user sees more documents (permission leak) or fewer documents (data loss) in Appwrite than in Postgres.
- **Success Criteria:** Exits `0` with 100% visibility symmetry across all sampled test users.

---

## 8. Phase 5: Production Traffic Cutover

Once Phase 4 passes:

### 8.1 Admin Portal Cutover (`CRADI-Mobile-Admin`)
1. In Vercel / hosting provider, update environment variables for production:
   ```env
   NEXT_PUBLIC_APPWRITE_ENDPOINT=https://fra.cloud.appwrite.io/v1
   NEXT_PUBLIC_APPWRITE_PROJECT_ID=6ac51e70002ab6238fec
   NEXT_PUBLIC_APPWRITE_DATABASE_ID=6941e2c2003705bb5a25
   NEXT_PUBLIC_APPWRITE_BUCKET_ID=report-images
   APPWRITE_API_KEY=<PRODUCTION_API_KEY>
   ```
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
- **Push Notification Transition:** As handsets update to the Appwrite release, the app registers the device's FCM/APNs token directly with Appwrite Cloud. Appwrite's `topics.js` background worker automatically reconciles topic subscriptions (`all-users`, `state-...`, `lga-...`).
- **Emergency Resilience:** During the client update window, critical hazard notifications remain safeguarded by direct Termii SMS alerts dispatched to local authorities and registered coordinators.

---

## 9. Phase 6: Post-Cutover Monitoring & Verification

Monitor the production environment for 48 hours post-cutover:

1. **Appwrite Functions Executions:**
   - Go to **Appwrite Cloud Console** $\to$ **Functions** $\to$ `worker` & `client`.
   - Monitor Execution Logs for runtime errors, out-of-memory errors, or timeouts ($> 15\text{s}$).
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
2. **Re-enable Supabase Writes:**
   ```sql
   DROP POLICY freeze_reports_write ON reports;
   DROP POLICY freeze_reports_update ON reports;
   DROP POLICY freeze_reports_delete ON reports;
   DROP POLICY freeze_verifications_write ON verifications;
   DROP POLICY freeze_profiles_write ON profiles;
   DROP POLICY freeze_alerts_write ON alerts;
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
