# Appwrite migration — Phase 1: schema and permission mapping

Status: **design, not agreed.** Nothing here has been built. This document is
the thing to argue with before anybody writes a migration.

Everything below was derived by applying `supabase/migrations/*.sql` to a real
Postgres and introspecting the result, not by reading the migration files. The
effective schema is **21 tables, 39 RLS policies, 24 triggers, 1 generated
column, 20 foreign keys, 18 CHECK constraints and 6 UNIQUE constraints**. (An earlier count of 58 policies was counting
redefinitions across migrations; 39 is what the database actually ends up
with.)

## Phase 0, in one line

A real Appwrite was stood up and the ward-scoped read rule was modelled against
it. Document ACLs of the form `read("user:<owner>")`, `read("team:<ward>")`,
`read("label:<role>")` reproduce `reports_select` exactly — 8/8 cases, list
queries filtered as well as single gets, Realtime filtered the same way, and
moving a user between wards is a team-membership change that touches no
document. **Reads are solved.** This phase is about everything else.

---

## The headline: reads are ACLs, writes are Functions

Appwrite permissions answer one question — *may this identity read/write this
document?* They cannot read the document's own values, and they cannot read
another collection. Two of our write rules do both:

```sql
-- reports_insert
user_id = auth.uid() AND is_enabled_user() AND status = 'pending'
  AND verification_count = 0 AND NOT escalated

-- verifications_insert
verifier_id = auth.uid() AND is_verifier()
  AND report_status(report_id)  = 'pending'
  AND report_owner(report_id)  IS DISTINCT FROM auth.uid()   -- not your own report
  AND (app_role() <> 'ewm' OR (report_ward(report_id) = my_ward()
                           AND report_lga(report_id)  = my_lga()))
```

`reports_insert` refuses a report that arrives already approved, already
verified or already escalated. `verifications_insert` refuses a vote on
somebody's own report, and reaches into `reports` to do it. Neither is
expressible as an ACL. A client with direct collection write could set
`status: 'approved'` on its own report, or vote for itself.

**So: reports, verifications and profiles are created and updated only through
Appwrite Functions, with the collection closed to client writes.** Reads stay
direct and ACL-filtered, which is what keeps the app fast and keeps Realtime.

This is not a workaround. It is the same boundary the database draws today —
it just moves from `WITH CHECK` into code we own, and we lose atomicity (see
*What we lose*).

---

## Collection map

21 tables → 19 collections, 2 dropped. `Writes` is the important column.

| Table | Cols | Collection | Writes | Notes |
|---|---|---|---|---|
| `profiles` | 20 | `profiles` | **Function** | Role, approval and ward are the inputs to every other rule. Never client-writable. |
| `reports` | 35 | `reports` | **Function** | `WITH CHECK` above. Widest table; see *Denormalisation*. |
| `verifications` | 8 | `verifications` | **Function** | Cross-collection check; cannot be an ACL. |
| `verification_overrides` | 6 | `verification_overrides` | **Function** | Staff-only, read by role label. |
| `alerts` | 12 | `alerts` | **Function** | `created_by = auth.uid()` plus role; generated column. |
| `authorities` | 8 | `authorities` | **Function** | Admin-only; composite FK into LGAs. |
| `contacts` | 11 | `contacts` | Client | Pure owner rule — `read/write("user:<id>")`. |
| `messages` | 10 | `messages` | Client | Owner + `label:approved`. |
| `trusted_devices` | 7 | `trusted_devices` | Client | Pure owner rule. |
| `login_history` | 8 | `login_history` | Client (insert) | Append-only, owner-stamped. |
| `ndpa_consents` | 6 | `ndpa_consents` | Client (insert) | Append-only, owner-stamped. |
| `knowledge_base` | 10 | `knowledge_base` | **Function** | Public read, admin write. |
| `news_links` | 8 | `news_links` | **Function** | Read rule depends on a mutable column — see below. |
| `app_settings` | 3 | `app_settings` | **Function** | Public read, admin write. |
| `scheduled_escalations` | 8 | `scheduled_escalations` | Server only | Written by the escalation job. |
| `notification_outbox` | 8 | — | Server only | **Replaced**, not migrated. See *The outbox*. |
| `sms_deliveries` | 7 | `sms_deliveries` | Server only | Delivery receipts from the Termii Function. |
| `nigeria_states` | 1 | — | — | **Dropped.** Static reference data that already ships in `lib/core/data/mvp_locations_data.dart`. |
| `nigeria_lgas` | 2 | — | — | **Dropped**, same reason. 53 LGAs, 584 wards, already in the app. |
| `alerts_unresolved_target` | 13 | `alerts_unresolved_target` | Server only | Quarantine table: RLS on, no policy, so service-role only today. Keep that shape. |
| `authorities_unresolved_coverage` | 10 | `authorities_unresolved_coverage` | Server only | As above. |

### Dropping the two location tables

`nigeria_states` (1 column) and `nigeria_lgas` (2 columns) exist to back
foreign keys. Appwrite has no foreign keys, and the same data is already
compiled into the app. Keeping them as collections would buy nothing but a
round trip. The composite FKs they serve —
`alerts.target_lga_canonical → nigeria_lgas(state, lga)` and
`authorities.coverage_lga → nigeria_lgas(state, lga)` — become validation
inside the write Function against the bundled list.

This is the one place the migration makes something *simpler*.

### Denormalisation

The foreign-key graph is a shallow star: 20 FKs, and almost every one points at
`profiles.id` or `reports.id`. There is no deep join to flatten. Three places
need a decision:

- **`reports` → reporter name/role.** The report list shows who filed it.
  Denormalise `user_name` and `user_role` onto the report at creation; accept
  that a later rename does not propagate, or fix it in the profile-update
  Function.
- **`verifications` → report ward/lga.** The verification write Function needs
  them to enforce the EWM rule, and it already has to read the report. Copy
  them onto the verification so the read path never needs the join.
- **`alerts` → report.** Nullable and rarely followed; leave as an id.

---

## Permission map — all 39 policies

Four patterns cover 35 of them. The remaining four are the work.

### Pattern A — public read (5 policies)
`alerts_select`, `knowledge_base_select`, `app_settings_select`,
`nigeria_states_select`, `nigeria_lgas_select`: `USING (true)`.
→ `read("any")` on the collection. Two of these disappear with the dropped tables.

### Pattern B — role (16 policies)
`app_role() = ANY (...)`, `is_admin()`, `is_staff()`, `is_verifier()`,
`is_approved_user()`.
→ Appwrite **labels**, set server-side on the user: `admin`, `techSupport`,
`ewv`, `ewr`, `ewm`, `ldp_coordinator`, `project_staff`, plus derived
`approved` and `enabled`. A document readable by staff carries
`read("label:ewv")`, `read("label:ewr")`, … one entry per role.

Labels are set only by the profile-update Function. A user cannot change their
own label, which is the property `app_role()` has today by reading `profiles`
under a `SECURITY DEFINER`.

### Pattern C — owner (9 policies)
`user_id = auth.uid()`, `sender_id`, `verifier_id`, `id = auth.uid()`.
→ `read("user:<id>")` / `write("user:<id>")` stamped at creation.

### Pattern D — ward (2 policies, the ones Phase 0 was for)
`reports_select` and `profiles_select` both carry
`app_role() = 'ewm' AND ward = my_ward() AND lga = my_lga()`.
→ `read("team:ward-<state>-<lga>-<ward>")`. **584 teams**, one per INEC ward.
Created in 14s on the spike; membership maintained by the profile Function.

Note the `COALESCE(my_ward(),'') <> ''` guard: an EWM with no ward set sees
nothing. Under teams this is automatic — no ward, no membership, no access.

### The four that do not fit

| Policy | Why | Decision |
|---|---|---|
| `news_links_select` | `is_active OR admin` — read depends on a **mutable column** | Re-stamp the ACL when `is_active` flips, in the write Function. Readable-while-active is not expressible, but "restamp on change" is exact. |
| `reports_update` | owner may update **only while `status = 'pending'`** | Write Function. Cannot be an ACL; the condition is on the row being written. |
| `verifications_select` | contains `EXISTS (SELECT 1 FROM reports …)` — a **join**, and the ward rule is inherited through it | Denormalise `ward`/`lga` onto the verification and stamp the matching team ACL. See below. |
| `verifications_insert` | reads `reports` for status, owner and ward | Write Function, as above. |

### `verifications_select` scopes by ward without saying so

The EWM arm reads:

```sql
app_role() = 'ewm' AND EXISTS (SELECT 1 FROM reports r WHERE r.id = verifications.report_id)
```

`verifications.report_id` is `NOT NULL` with a foreign key to `reports.id`, so
the row it looks for always exists and the subquery looks like it can never be
false. It is not a no-op. **A subquery inside a policy expression is itself
subject to RLS**, so that `SELECT … FROM reports` is filtered by
`reports_select` — and resolves to "a report this EWM is allowed to see",
which is their own ward.

Verified against the schema rather than reasoned about: with a ward-A EWM
signed in, `exists(select 1 from reports where id = <ward-B report>)` returns
false while the same query for the ward-A report returns true, and the
superuser sees both rows. An earlier draft of this document called the clause
a no-op and the policy a live over-permission. That was wrong, and the fix it
recommended would have changed nothing.

**But it does not survive the migration.** The scoping here is transitive: the
visibility of a verification is defined by the visibility of its report, and
nothing in the verification row says so. Appwrite has no inheritance of that
kind — a document's ACL is the whole of its access rule, and no part of it can
be "whatever the related document allows".

So the mapping is unchanged, and now better motivated: the write Function
copies `ward` and `lga` onto each verification (it reads the report anyway, to
enforce the insert rule) and stamps the same `read("team:ward-…")` the report
carries. What Postgres derives at query time becomes something Appwrite is
told at write time.

The cost is that the two can now drift. If a report's ward is ever corrected,
its verifications must be restamped — a case the current schema cannot have,
because it never stored the answer twice.

---

## Trigger map — all 24

| Kind | Count | Where it goes |
|---|---|---|
| `*_touch` (BEFORE UPDATE, sets `updated_at`) | 9 | The write Function, or `$updatedAt` which Appwrite maintains for free. Mostly disappears. |
| **BEFORE guards** | 6 | `reports_before_insert`, `reports_guard`, `profiles_guard`, `profiles_guard_approval`, `alerts_guard_author`, `messages_before_write`. These enforce invariants *atomically, before commit*. They become the body of the write Functions. **This is where the risk is.** |
| **AFTER side effects** | 9 | `reports_after_insert`, `reports_after_status_change`, `reports_audit_decision`, `alerts_after_insert`, `profiles_after_access_change`, `verifications_after_{insert,update,delete}`, `verifications_after_insert_dispute`. Map to Appwrite **event Functions** (`databases.*.collections.reports.documents.*.update`). Already asynchronous in spirit — they queue notifications and write audit rows. |
| Generated column | 1 | `alerts.target_lga_canonical` — compute in the write Function. |

---

## The outbox

`notification_outbox` + `claim_outbox_events` exist because the Railway worker
needed to claim rows without two instances sending the same SMS twice. The
claim is `SELECT … FOR UPDATE SKIP LOCKED`, which Appwrite has no equivalent
for.

Options, in order of preference:

1. **Let Appwrite Messaging own it.** Push and email become Messaging
   deliveries with no queue of ours. The outbox stops existing for those two
   channels.
2. **SMS keeps a queue**, because Termii stays (your decision) and is called
   from a Function. A single scheduled Function with a concurrency of one
   removes the need to claim at all — there is only ever one reader.
3. If that is not enough, a claim document with optimistic concurrency on
   `$updatedAt`.

`sms_deliveries` survives either way as the receipt log.

---

## What we lose

Stated plainly, because these are the costs of the decision, not objections to it.

1. **Atomicity.** Six BEFORE guards currently run inside the transaction. In
   Appwrite the Function validates and then writes — two steps. A concurrent
   write between them is a race the database used to make impossible. The
   mitigations are: make the Function the only writer (collection closed to
   clients), and make every guard idempotent.
2. **`verification_count`.** Maintained today by AFTER triggers on
   `verifications` and read by `reports_insert`'s `WITH CHECK`. As an event
   Function it becomes eventually consistent — the count can lag a vote. Any
   rule that *gates* on it must read the verifications collection instead of
   trusting the cached number.
3. **18 CHECK constraints and 6 UNIQUE constraints.** Appwrite has no CHECK.
   Uniqueness exists only as a unique index on an attribute, so composite
   uniqueness must be enforced by a deterministic document ID — e.g. a
   verification's ID becomes `<reportId>_<verifierId>`, which makes
   "one vote per verifier per report" structural rather than checked.
4. **`roles_e2e.sql` — 351 assertions.** The evidence the access model works.
   It has no Appwrite equivalent and must be rewritten as integration tests
   against a live project, driving real sessions as each role. Budget this as
   its own piece of work; without it the migration ships with no proof that an
   EWM in one ward cannot read another's reports.

---

## Open, and blocking Phase 2

1. **Region.** The old project ran on `fra.cloud.appwrite.io` — Frankfurt. The
   app records `dataResidency` on NDPA consent. If in-country residency has
   been promised, Appwrite Cloud may not be able to provide it and the hosting
   decision reopens. Not checkable from this container: the egress proxy
   refuses `appwrite.io` and `fra.cloud.appwrite.io` alike.
2. **Cloud quotas.** 584 teams, 19 collections, and more than one storage
   bucket. The old config carries the comment *"free tier limits (max 1
   bucket)"*, so the tier matters. Needs the real project to confirm.
3. ~~`verifications_select`'s `EXISTS`.~~ **Resolved.** Checked against the
   schema: the subquery inherits `reports_select` through RLS, so the policy
   is correct as written. Nothing to fix in Supabase; the Appwrite mapping
   makes the inherited scope explicit instead.

---

# Phase 2: auth

Status: **verified against a running Appwrite 1.6.2**, not merely designed.
Every claim below was executed; the sequences are reproducible from
`appwrite-spike/spike/auth*.mjs`.

## The headline: the typed-code flows survive intact

The app asks users to type a code, in two places — `/verify-otp` after
registration and `/reset-password` for recovery. Appwrite's own verification
and recovery endpoints are **link-based**: `POST /account/verification` and
`POST /account/recovery` both require a `url`, email a link containing
`userId` and `secret`, and return an empty `secret` to the caller. Taken at
face value, the app's whole code-entry UX would have had to be rebuilt as
links.

It does not, because of one endpoint:

```
POST /v1/users/{userId}/tokens   {"length": 6, "expire": 900}   (server, API key)
  -> 201 {"secret": "251152", ...}
```

A server-minted token of **any length we choose**, which the user can type and
redeem for a real session. Verified end to end:

| Step | Call | Result |
|---|---|---|
| 1. mint | `POST /users/{id}/tokens {length:6}` | `201`, secret `"251152"` |
| 2. user types it | `POST /account/sessions/token {userId, secret}` | `201`, session established |
| 3a. verification | `PATCH /users/{id}/verification {emailVerification:true}` | `200`, `emailVerification=true` |
| 3b. recovery | `PATCH /users/{id}/password {password}` | `200` |
| 4. new password works | `POST /account/sessions/email` | `201` |
| 5. old password refused | `POST /account/sessions/email` | `401` |
| — wrong code | `POST /account/sessions/token {secret:"000000"}` | `401` |

So both flows become: a Function mints the token, **we** send the email
through Messaging with our own wording, the user types six digits, and the
Function completes the action. Appwrite's link endpoints are not used at all.

**This deletes a whole class of bug we have already paid for once.** The
`redirectTo` defect — a recovery link built from the project's Site URL,
landing app users on the admin portal — cannot occur in a design with no link
in it. `VITE_AGENT_APP_URL`, deep-link handling for recovery, and
`kPasswordResetRedirect` all become unnecessary for this flow.

The cost is that the email template moves from the provider's console into our
Function, and the OTP length becomes our decision rather than a dashboard
setting. Given we shipped a bug last month because the dashboard said 8 while
the app's copy said 6, that is an improvement.

## Call-by-call map

Eleven distinct Supabase auth calls are in use across `auth_provider.dart`,
`profile_provider.dart` and `supabase_service.dart`.

| Today (Supabase) | Appwrite | Where |
|---|---|---|
| `auth.signUp(email, password, data:)` | `POST /users` + profile document | **Function** — metadata becomes the `profiles` document, which is Function-written anyway |
| `auth.signInWithPassword` | `POST /account/sessions/email` | Client |
| `auth.verifyOTP(type: signup)` | `POST /account/sessions/token` then `PATCH /users/{id}/verification` | Client + Function |
| `auth.verifyOTP(type: recovery)` | `POST /account/sessions/token` then `PATCH /users/{id}/password` | Client + Function |
| `auth.resend(type: signup)` | mint a fresh token, send again | Function |
| `auth.resetPasswordForEmail` | mint token, send our own email | Function |
| `auth.updateUser(password:)` | `PATCH /account/password` (knows the old one) | Client |
| `auth.updateUser(email:)` | `PATCH /account/email` | Client |
| `auth.refreshSession` | `PATCH /account/sessions/{id}` — verified `200`, expiry extended | Client |
| `auth.currentSession` | `GET /account` / `GET /account/sessions` | Client |
| `auth.signOut` | `DELETE /account/sessions/{id}` (verified `204`) or `/sessions` for all | Client |
| `auth.signInWithOtp` (phone) | — | Not migrated. `AuthProvider.phoneAuthEnabled` is `false` and every phone control is hidden behind it. |

## Sessions, and what they do not replace

Appwrite sessions default to a **one-year** expiry and are refreshable in
place. `GET /account/sessions` returns `ip, osName, osVersion, clientName,
clientVersion, deviceName, deviceBrand, deviceModel, countryName, current` —
and a single session can be deleted, which is "sign out that device".

That covers the *listing and revoking* half of `trusted_devices`. It does not
replace either table:

- **`trusted_devices`** also carries `trusted` and our own
  `device_fingerprint` from `DeviceFingerprintService`. Appwrite derives its
  own fingerprint from the user agent and has no notion of trust. Keep the
  collection; join it to sessions on our fingerprint.
- **`login_history`** records `success`, including **failed** attempts, and a
  `risk_score` from `FraudDetectionService`. A session only exists when
  sign-in succeeded, so the failures — the rows that matter most — have
  nowhere to live. Keep the collection and keep writing it.

## Biometric unlock

`authenticateWithBiometrics` re-uses the persisted session and refreshes it if
expired; `_isServerSessionValid()` is the server check. Both map directly:
`GET /account` to validate, `PATCH /account/sessions/{id}` to extend. The
local half — `BiometricService`, the lock screen, `SecureSessionStorage` —
does not touch the backend and is unaffected.

The session secret must continue to live in `flutter_secure_storage`, as it
does today.

## Risks

1. **The API key cannot ship in the app.** `POST /users/{id}/tokens` is a
   server call. Every mint happens in a Function, which is also where the
   abuse limits have to live — Supabase's per-address recovery throttle is a
   dashboard setting today and becomes our code.
2. **Token expiry is ours to choose.** Supabase's OTP expiry is a project
   setting; here it is the `expire` argument. 900s matches the current
   3600s loosely — pick deliberately and write it down.
3. **Enumeration.** `POST /account/recovery` deliberately does not reveal
   whether an address exists. Our Function must preserve that: always answer
   the same, mint nothing for an unknown address.
4. **Tested on 1.6.2 self-hosted.** The auth API is stable across 1.x, but
   this has not been run against Cloud — see the open items, which still
   stand.

## Not in scope here

Storage, Messaging providers, the Termii Function, data migration and cutover.
Those are Phases 3 and onward.
