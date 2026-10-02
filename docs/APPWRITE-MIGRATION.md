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

---

# Phase 3: storage and messaging

Status: **verified against the running Appwrite**, except the two provider
integrations that need real credentials (FCM, Termii). Scripts:
`docs/appwrite-spike/storage*.mjs`, `messaging.mjs`.

## Storage

Two buckets today, `profile-images` and `report-images`, both **public-read**,
object paths prefixed with the uploader's user id and enforced by storage RLS.
Report images upload with `upsert: false` because evidence must not be
replaced.

### ImageKit goes away

`ImageUrlResolver` routes storage URLs through an ImageKit endpoint for CDN
delivery and resizing. It is already optional — `IMAGEKIT_URL_ENDPOINT` is a
`String.fromEnvironment` that is empty unless set at build time, and when
empty every URL passes through untouched. Delivery only: no SDK, no uploads.

Appwrite Storage does the same job natively. Measured on a 1600×1200 JPEG:

| Request | Result |
|---|---|
| `/files/{id}/preview` | `200 image/jpeg` 11,538 B |
| `/preview?width=300&height=300` | `200 image/jpeg` 830 B |
| `/preview?width=300&quality=60&output=webp` | `200 image/webp` **210 B** |

Width, height, quality and format conversion, including WebP. **Drop
ImageKit**, and with it `ImageUrlResolver.resolve`, the
`supabasePublicMarker` parsing and the build-time endpoint.

### And possibly the second upload

`ReportingProvider` uploads a thumbnail next to each photo, named by
convention (`thumbStoragePath`) so nothing extra has to be persisted. With
`preview?width=` available, that upload is redundant — one file per photo
instead of two, half the storage, half the upload time on a field connection.

The catch is named in `ImageUrlResolver`'s own comment: thumbnails are covered
by the `reports.image_urls` immutability guard precisely *because* they are
stored objects. Deriving them instead means the guard covers one URL, not two.
Worth doing, but it is a change in what is guaranteed, not just a saving.

### Evidence immutability gets stronger

`upsert: false` is a convention today — the code catches the duplicate error
and treats it as success. In Appwrite a file id can only be created once:

```
POST /storage/buckets/report-images/files  fileId=ev-001  -> 201
POST  (same fileId again)                                 -> 409
```

Structural rather than conventional. The deterministic per-report-and-index
path becomes a deterministic file id.

### The one real decision: public-read, or ward-scoped?

Today a report photo is world-readable to anyone holding the URL, while the
report it belongs to is ward-scoped. That asymmetry is pre-existing and may be
deliberate — an unguessable URL is not nothing — but Appwrite can close it,
because **file permissions work exactly like document permissions**. Verified
with a file stamped `read("team:ward-benue-makurdi-north")`:

| | `view` | `preview` |
|---|---|---|
| EWM in that ward | `200` | `200` |
| user in no ward team | `404` | `404` |

The transformation endpoint honours the ACL too, so a thumbnail cannot be used
to peek at an image the viewer may not see.

**The cost is delivery.** An ACL'd file cannot be a plain `<img src>` to an
unauthenticated CDN; every fetch carries the session, and shared caching gets
harder. That is a product decision about whether evidence photos are public,
not a technical blocker. Flagging it rather than choosing.

## Messaging

### Push: OneSignal's four targeting modes

| Today | Appwrite |
|---|---|
| `sendToUsers(ids)` → `include_aliases.external_id` | `users: [...]` — verified `201` |
| `sendToTag('lga', v)` | topic `lga-<state>-<lga>` |
| `sendToTags({lga, state})` | one topic at the finest granularity; Appwrite has no AND of filters |
| `sendToAll()` → segment | topic `all-users` |
| `idempotency_key` | **the `messageId` itself** |

That last row is the nicest result of this phase. OneSignal needed a
UUID-shaped idempotency key derived from the outbox row. Appwrite refuses a
duplicate message id outright:

```
POST /messaging/messages/push  messageId=outbox-event-92  -> 201
POST  (same id again)                                     -> 409
```

So the outbox event id becomes the message id and double-send is impossible by
construction, not by convention.

### Tags become topics, and there are a lot of them

The app sets `role, lga, state, ward, monitoring_zone` on login
(`backend/src/tags.js`). As topics that is roughly 3 states + 53 LGAs + 584
wards + 8 roles + zones + `all-users` — **650 or more**, maintained alongside
the 584 ward *teams* from Phase 0. Teams carry access; topics carry delivery;
both are driven by the same profile Function.

Two structures of that size on one project is the sharpest version of the
quota question still open.

An honest alternative: if ward-level push is not actually used, drop the ward
topics and target `users: [...]` from a Function that queries the ward team.
Worth checking against real usage before building 584 of anything.

### Email: Resend → Appwrite Messaging

A provider swap, not a redesign. The 154 lines of `email/templates.js` move
into the Function that sends them, which is where Phase 2 already puts the
verification and recovery mail.

### SMS: Termii stays

Your decision, and the right one — the sender IDs and delivery rates are
already proven in Nigeria, and Termii is not an Appwrite Messaging provider.
SMS therefore does **not** go through Messaging: a Function calls Termii
directly, exactly as `backend/src/sms/providers.js` does today.

Consequence: `sms_deliveries` stays as the receipt log, and the SMS half keeps
a queue of its own while push and email lose theirs.

## The migration risk nobody can engineer away

**OneSignal subscriptions cannot be transferred.** A push target in Appwrite
is a device token registered by the Appwrite SDK; OneSignal player ids are
meaningless to it. Every device must re-register on first launch of the new
build.

So on cutover, **push reaches nobody until each user opens the app at least
once**. For an early-warning platform that is the one channel that matters,
and the gap is as long as a user's quietest week.

Mitigations, none free:

- Ship the Appwrite SDK registering targets *before* cutover, so tokens exist
  on the day. Means a release that talks to both backends.
- Announce by SMS, which survives the cutover untouched because Termii stays.
- Accept the gap and watch target registration climb before decommissioning
  OneSignal.

This belongs in the cutover plan (Phase 7), but it is decided here, because
the first mitigation changes what Phase 3 builds.

---

# Phase 4: Functions, and the write path

Status: **built and executed**, not designed. Phases 1–3 each concluded "this
becomes a Function" without anything proving Functions work. They do.

A numbering note: the original sketch had the client data layer at Phase 3 and
notifications at Phase 4. Storage and messaging were merged into Phase 3
instead, so the data-layer swap is now Phase 5.

## What was built

`docs/appwrite-spike/fn/create-report` is a real deployed Function standing in
for `reports_insert`'s `WITH CHECK` and the `reports_before_insert` trigger.
It reads the caller's profile, refuses a disabled account, fixes `status`,
`verification_count` and `escalated` itself, resolves the ward to a team id,
and creates the document with the ACL Phase 0 designed.

## The write path, proven

| | Result |
|---|---|
| Client writes `reports` directly | **`401`** — the collection is closed |
| Client calls the Function | `201` — `status: "pending"`, stamped `ward-benue-makurdi-north` |
| Client sends `status:"approved", verification_count:99, escalated:true` | `201` — and the stored document is still **`status: "pending"`** |
| EWM in that ward reads it | `200` |
| `ewv` label reads it | `200` |
| Owner reads it | `200` |
| Outsider: no team, no label, not the owner | **`404`**, and `listDocuments` returns **0** |

The third row is the one that matters. It is the `WITH CHECK` the database
used to enforce, now enforced in code the client cannot reach — and the
client's attempt to pre-approve its own report changed nothing.

## Event Functions replace the AFTER triggers

A Function registered on
`databases.cradi.collections.reports.documents.*.create` fired on the write
above:

```
trigger=event  status=completed
EVENT databases.cradi.collections.reports.documents.6abf…28.create
      doc=6abf…28 ward=North status=pending
```

The whole document arrives in the body and the event name in
`x-appwrite-event`. That is the mapping for all nine AFTER triggers
(`reports_after_insert`, `reports_after_status_change`, `verifications_after_*`
and the rest).

The same Function accepted `schedule: "*/15 * * * *"` alongside its events,
which is the shape the escalation cron needs. **The schedule was accepted, not
observed firing** — a fifteen-minute wait was not spent. Worth confirming
before Phase 6 depends on it.

## Latency, measured

| | |
|---|---|
| Cold start | **735 ms** |
| Warm | **34–39 ms** function, 71 ms round trip |

Report submission is now a Function call rather than a direct insert, so a
field user's write carries that cost. Warm is negligible. Cold is not nothing,
and runtimes are scaled down after an inactivity threshold — on a quiet night
in a quiet ward, the first report of the morning pays it.

Measured on an idle local box with no network between client and API. A real
Nigerian mobile connection adds its own round trip to both numbers; these are
a floor, not a forecast.

## Operational findings

None of this applies to Appwrite Cloud, which runs the plumbing for you. All
of it applies if self-hosting is chosen after the region question is settled —
and each cost real time here:

1. **The executor listens on port 80**, not 3000. `_APP_EXECUTOR_HOST` must be
   `http://exc1/v1`.
2. **The API, the builds worker and the functions worker must share
   `/storage/functions` and `/storage/builds`** with the executor. Without it
   the build fails with a bare `File Not Found`, which names nothing.
3. **The runtimes network must be shared and named exactly `runtimes`.** The
   executor attaches runtime containers through the Docker socket to a network
   of that literal name; Compose otherwise creates `<project>_runtimes`, the
   runtime lands where the executor cannot reach it, and every execution dies
   with `Function timed out during cold start` **while the runtime's own log
   says `HTTP server successfully started!`**. That contradiction is the
   signature of this bug and it cost the most time of anything in this spike.
4. **Give MariaDB a volume.** `docker compose down` on a volumeless MariaDB
   destroys the project, its collections, its users and every deployed
   Function. It did, here, and the only reason it was cheap is that the spike
   is scripted — `setup.mjs`, `addscopes.mjs`, `spike.mjs`, `deployfn.mjs`
   rebuilt the whole thing, and Phase 0's eight assertions passed again
   afterwards, which is a reproducibility check nobody planned.

## What this leaves

The design of every phase so far now rests on something executed rather than
assumed. What is still unproven: the scheduled trigger actually firing, and
anything at all about Cloud — region, quotas, and whether 584 teams and ~650
topics are allowed on the tier you buy.

---

# Phase 5: the client data layer

Status: **the seam is built and in `main`-shaped code**, not a spike. 679
tests pass, `dart format` is clean, and no behaviour changed.

## What the coupling actually was

Nine Dart files imported `supabase_flutter`. The obvious reading is "nine
files to edit". The real finding is worse and more interesting: the app's
**business logic was branching on Postgres SQLSTATEs**.

```dart
if (error is PostgrestException) {
  switch (error.code) {
    case '22023': return l10n.reportActionErrorAlreadyPending;
    case 'P0002': return l10n.reportActionErrorGone;
    case '42501': …
```

Those codes are not incidental. The migrations raise them deliberately —
`42501` appears **41 times** as the guards' way of saying "refused", `54000`
is the chat rate limit, `22023` means "that report is no longer pending". The
database's error vocabulary *was* the app's error vocabulary.

Under Appwrite none of those codes exist. A Function answers 403, or returns
a shape we choose. So this had to be named before anything could be swapped.

## The seam

`lib/core/services/backend_failure.dart` — a vocabulary of what happened,
not of which engine said so:

| `BackendFailure` | Postgres today | Meaning |
|---|---|---|
| `refused` | `42501`, `PGRST301` | a guard said no |
| `rateLimited` | `54000` | too fast |
| `notFound` | `P0002` | the row is gone |
| `invalidState` | `22023` | exists, but not in a state that allows this |
| `duplicate` | `23505` | uniqueness |
| `constraint` | `23514`, `23503` | CHECK or foreign key |
| `unknown` | anything else | treat generically; do not guess |

Four pluggable readers sit beside it, each answering a question only the
adapter can:

- `backendFailureOf` — which of the above.
- `backendMessageOf` — is there wording worth showing a field agent? Narrow
  on purpose (see below).
- `backendDiagnosticOf` — what exactly did the server say, for the record
  stored against a rejected report.
- `isBackendTransient` / `isBackendPermanent` — is a queued write worth
  retrying?

`SupabaseService.installErrorVocabulary()` registers all of them. An Appwrite
adapter installs its own, and every call site is untouched.

## Three things the move surfaced

**1. The "row-level" heuristic was in the wrong place.** `reportActionError`
showed the server's message for a trigger refusal but hid it for a bare RLS
denial, by testing whether the text contained `row-level`. That is
Postgres-specific knowledge sitting in a feature file. It now lives in the
adapter, which returns `null` for messages not worth showing — so the call
site reads `backendMessageOf(error) ?? l10n.reportActionErrorNoPermission`
and knows nothing about PostgREST's phrasing.

**2. The retry policy was the most consequential leak.** `isPermanentSyncError`
decided whether a field agent's queued report is retried or **marked rejected
and never sent**, and it decided it from a set of nine SQLSTATEs and a range
of storage HTTP statuses, in `offline_storage_service.dart`. On another
backend that set means nothing, the predicate silently answers "not
permanent", and reports retry forever — or worse, the inverse. It is now the
adapter's, where a new backend must consciously answer the same question.

**3. `admin_screen` was bypassing the service entirely**, building
`client.from(table).count(...)` by hand — and deliberately, because
`countDocuments` swallows errors as `0` and the dashboard's comment says a
misleading zero is worse than an error. That is correct, and it is the same
bug this project shipped once in the admin operations panel. So the service
gained `countDocumentsOrThrow`, and `countDocuments` now delegates to it; the
screen keeps its behaviour and loses the raw client.

## Result

| | before | after |
|---|---|---|
| Files importing `supabase_flutter` | 9 | **4** |
| SQLSTATEs in feature code | 4 sites | **0** |
| Postgres codes outside the adapter | several | **0** (one doc comment) |

The four remaining are the adapter itself, and three files coupled to **auth**
types (`sb.User`, `sb.AuthException`, `sb.UserAttributes`) rather than to
data: `auth_provider.dart` (116 references), `profile_provider.dart` and
`chat_screen.dart`.

## Why auth is deliberately not done here

`auth_provider.dart` is the largest and most security-sensitive file in the
app, Phase 2 already maps all eleven of its backend calls, and rewriting it
means replacing sessions, OTP verification, recovery and biometric unlock at
once — against an Appwrite instance the app cannot yet talk to, for a
migration whose hosting question is still open.

The data seam is worth having regardless of whether Appwrite proceeds: it
removes engine-specific codes from business logic, it puts the retry policy
where a reviewer can find it, and it is the difference between a swap that is
mechanical and one that is archaeology. Auth should follow the same shape,
once there is something to point it at.

---

# Phase 6: the worker

Status: **the two questions this phase existed to answer are answered**, both
by experiment. The verdict is less convenient than hoped.

## 1. Scheduled Functions fire

Phase 4 accepted a cron schedule but never watched one run, and said so.
Watched now:

```
08:24:00  trigger=event     completed
08:24:37  trigger=event     completed
08:43:00  trigger=schedule  completed      <- on the minute
```

The escalation cron has a home. One caveat for self-hosting: this needs the
`schedule-functions` and `schedule-executions` services. My minimal stack
lacked both, so schedules silently never fired — which looks exactly like
"Appwrite cron does not work". Two minutes of waiting would have produced a
confident wrong answer.

## 2. Event Functions are fire-and-forget, and that is the whole problem

A Function registered on document-create that throws every time, given one
event, watched for three minutes:

```
t+0s …  t+170s   executions=1   08:43:40 event/failed
```

**One execution. No retry. Ever.** The event is gone.

That settles the outbox's fate, because at-least-once delivery is the only
reason it exists.

## What `claim_outbox_events` actually guarantees

```sql
update notification_outbox o
   set attempts = o.attempts + 1,
       available_at = now() + make_interval(mins => least(60, power(2, o.attempts)::int))
 where processed_at is null and available_at <= now() and attempts < 8
 limit p_limit
   for update skip locked
```

Four properties, and Appwrite provides none of them:

| Property | Appwrite |
|---|---|
| Atomic claim (`for update skip locked`) | no equivalent |
| Exponential backoff, capped at 60 min | ours to write |
| Give up after 8 attempts | ours to write |
| At-least-once | **event Functions are at-most-once** |

So **the outbox is not deleted. It is rebuilt**, as an Appwrite collection
drained by a scheduled Function.

## The shape

```
report written by a Function
      │
      ├─ event Function  ──>  writes ONE outbox document (nothing else)
      │
scheduled Function (every minute)
      ├─ reads outbox documents that are due
      ├─ sends push/email via Messaging, SMS via Termii
      └─ marks processed, or backs off and increments attempts
```

The five handlers — `report_created`, `report_status_changed`,
`report_disputed`, `user_access_changed`, `alert_created` — move from
`backend/src/outbox.js` into the drain Function essentially unchanged. They
are already written against a `repo` and a `push` interface.

### Why the claim stops mattering, mostly

Two scheduled runs could overlap and claim the same row, and there is no
`skip locked`. For **push and email it does not matter**: Phase 3 showed
Appwrite refuses a duplicate `messageId` with `409`, so the outbox id becomes
the message id and the second send is refused by the server. Idempotency
replaces locking.

**SMS is different.** Termii has no such protection and would send twice —
and a duplicate flood warning to an authority is not a harmless retry. So
`sms_deliveries` becomes the claim: a document whose id is deterministic per
outbox event and recipient, inserted *before* the send. Verified:

```
first  insert of a deterministic id -> 201
second insert of the same id       -> 409   (the claim is taken)
```

A unique document id is the lock primitive this design rests on, and it is
the same one that makes evidence files immutable in Phase 3.

## The loss that has no clean mitigation

Today the outbox row is written **by a trigger, inside the same transaction
as the report**. Either both exist or neither does.

In Appwrite the event Function runs *after* the write commits, and can fail —
cold start timeout, runtime crash, a bad deploy. When it does, there is a
report in the database with no outbox row, no notification, and **nothing
that will ever notice**. The suite of guarantees that made the outbox
trustworthy started one step earlier than the outbox.

The honest mitigation is a reconciling sweep: a scheduled Function that looks
for reports created in the last N minutes with no corresponding outbox
document and writes the missing ones. It is not free, it is not exact, and it
has to be built — but without it the platform can silently fail to warn
somebody, which is the one failure this system exists to prevent.

This should be weighed against the hosting decision. A trigger that is
transactional with the write is a real property of the current design, and
losing it is a cost that does not appear in any feature comparison.

## What is now proven, end to end

Everything the design depends on has been executed rather than assumed:
ward-scoped reads and lists, Realtime filtering, typed-code auth, image
transformation, file ACLs, message idempotency, closed-collection writes
through a Function, event triggers, scheduled triggers, the absence of event
retries, and the deterministic-id lock.

---

# Phase 7: data migration and cutover

Status: **the pipeline is built and run end to end** against the real schema
(all 14 migrations applied to Postgres) and a real Appwrite. Only the
endpoint changes for Cloud. Scripts: `docs/appwrite-spike/migrate/`.

This phase was listed as blocked on the Cloud answers. The *real run* still
is — there is nothing to export into. The pipeline is not, and building it
first turned up four defects that would each have been found at 2am during a
cutover window instead.

## Shape

```
export (SQL)  ->  transform + stamp ACLs  ->  import (REST)  ->  reconcile
```

Identities first, always: `seed-identities.mjs` creates a user per profile, a
team per ward, a label per role. Then `migrate.mjs` writes profiles, reports
and verifications, each stamped with the ACL that reproduces the RLS policy
it used to live under. Every document keeps its Postgres uuid as its Appwrite
id, so a re-run collides with `409` rather than duplicating — the same
property Phase 6 uses for the SMS claim.

Result on the fixture: 6 profiles, 4 reports, 2 verifications, 3 ward teams,
0 orphans.

## Reconciliation is not row counts

Row counts are the obvious check and they are nearly worthless here. The
difficulty of this migration is access control, so the only question worth
asking is:

> does each user see exactly what Postgres would have shown them?

`reconcile.mjs` answers it by querying the live RLS policy **as that user**
(`set_config('request.jwt.claim.sub')`, `set role authenticated`) and the
Appwrite collection **with that user's session**, then diffing the id lists.

```
user                      role   postgres  appwrite  verdict
EWM Centre               ewm           1         1  match
EWM North                ewm           2         2  match
EWV State                ewv           4         4  match
Citizen Centre           user          1         1  match
Citizen North            user          2         2  match
Citizen Obi              user          1         1  match
```

Both directions matter. Granting too much is worse than granting too little
and both are silent.

**Proven to detect a breach, not just to pass.** Granting one ward's team
read on another ward's report — a plausible slip — moves EWM Centre from 1 to
2 and the run exits `1`. Reverted, it exits `0`. It belongs in CI for the
cutover.

## Four defects the pipeline found

Each was silent. Each would have produced a migration that looked complete.

**1. Appwrite labels cannot contain underscores.** `ldp_coordinator` and
`project_staff` are rejected (`400`); `ldpCoordinator` and `projectStaff` are
accepted. So every role with an underscore needs a second spelling, and
`roleLabel()` must be the *only* one — used by the migrator, the identity
sync and the write Functions alike. If any two disagree, the ACL names a
label nobody holds, **Appwrite accepts it without complaint**, and that role
silently sees nothing. It reads as empty data, not as a permissions bug.

**2. An id transformation in one place and not the other.** The first draft
stripped dashes from the uuid when creating users and kept them when stamping
`read("user:…")`. Every row migrated perfectly and **nobody could read
anything**. The fix was to delete the transformation: a Postgres uuid is 36
characters and Appwrite allows dashes after the first, so it is a valid user
id verbatim. `appwriteUserId()` exists as the identity function purely so
there is one place for anybody tempted to transform it again.

**3. Synthesised email addresses collide.** Deriving a local part from
`id.slice(0,8)` gave every profile the same address, and five of six users
failed to create — counted, not reported, because the first version of the
script only counted `201`s. Addresses come from `auth.users` and nowhere
else.

**4. Appwrite validates emails more strictly than Postgres stores them.**
A single-label domain is refused. A real export will contain addresses
Appwrite will not accept, and those users cannot be created at all. **This
needs a pre-flight pass over `auth.users` before any cutover window opens**,
not a discovery inside one.

## And one in the checker itself

The first reconciler asked for `queries[]=limit(100)`, which this version
rejects as a syntax error, and then read `body.documents ?? []`. It turned a
`400` into "this user can see nothing" and **reported a total migration
failure for a migration that was correct**.

A reconciler that reads an error as an empty result is worse than no
reconciler, because its verdict is confident. It now throws on any non-OK
response and paginates with the JSON query form.

That is the second time in this project a swallowed error produced a
confident wrong answer — the first was `browser-test.sh` exiting 0 with
twenty failures. Worth a standing rule: **a checker may not treat a failed
request as a negative result.**

## Cutover

Order follows the dependencies the pipeline exposed:

1. **Pre-flight** — validate every `auth.users` email; list the ones Appwrite
   will refuse and fix them in Supabase first.
2. **Identities** — users, ward teams, role labels. Nothing may be stamped
   before the thing it names exists.
3. **Freeze writes** (or dual-write; see below).
4. **Data** — profiles, reports, verifications, then the rest.
5. **Reconcile** — per-user visibility, exit non-zero on any difference.
6. **Switch the app**, then decommission.

Two things from earlier phases land here:

- **Push reaches nobody until each user opens the app** (Phase 3). OneSignal
  subscriptions cannot be transferred. For an early-warning platform this is
  the sharpest cutover cost, and the mitigation — shipping the Appwrite SDK
  registering targets before cutover — has to happen *before* this phase, not
  during it.
- **The reconciling sweep for reports with no outbox row** (Phase 6) should
  exist before go-live, not after.

The freeze window is the open question the fixture cannot answer: it depends
on row counts nobody has measured against the production database, and on
whether a dual-write period is acceptable. Both need the Cloud project.

---

# Phase 8: decommissioning, and the credential inventory

Status: **nothing has been decommissioned, and nothing should be.** No
production migration has run. Tearing down Supabase, Railway, OneSignal or
Resend now would destroy a working early-warning system for a migration that
exists only as a tested pipeline.

What this phase delivers is the part that is safe and overdue: an inventory
of every credential in both repositories' full history, from an actual scan
rather than a list written from memory — and a rotation order that does not
depend on the migration happening at all.

## The scan

183 commits in `CRADI-mobile`, 55 in `CRADI-Mobile-Admin`, every one grepped
for vendor-anchored patterns (`standard_`, `os_v2_`, `re_`, `sb_secret_`,
`TL…`, `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.`, PEM headers). Both
repositories are **public**.

### Real, and compromised

| Secret | Where | Reach |
|---|---|---|
| **2 × Appwrite server API keys** (`standard_…`, 265 chars) | `CRADI-mobile` history: `DEPLOYMENT_STEPS.md`, `docs/DEPLOYMENT_STEPS.md`, `ESCALATION_FIX_STATUS.md`, `scripts/update_schema.js`. One also in `CRADI-Mobile-Admin` history. | Full server access to the old Appwrite project |
| **2 × Termii API keys** | `CRADI-mobile` history: `test_termii.dart`, `test_termii_otp.dart` | **Can send SMS and spend money** |

Neither is in current `main`. Both are readable by anyone with `git log -p`.

### Not secrets — no action

- **Supabase anon key** in `README.md`, on current `main`. Decoded, its
  payload is `"role":"anon"`: the publishable key, designed to ship in every
  client. RLS is the protection, not this string.
- **`ONESIGNAL_REST_KEY`** in `.env.example` — the value is
  `os_v2_app_…gnal-rest-key`, a placeholder.
- **`re_implementations`** — an English word that matches Resend's prefix.
- **npm `sha512-` integrity hashes** and base64 inside `chain.pem` — these
  matched a Termii-shaped pattern and are not keys. Checked individually
  rather than reported.

### A correction

Earlier in this project I told you the **OneSignal REST key was in public git
history** and should be rotated. That was wrong. The only occurrence is the
placeholder above. I cannot substantiate the claim and should not have made
it.

## Rotation, which does not wait for the migration

Your instruction was to keep the current keys until the app is fixed and
rotate at the end. That is reasonable for keys whose only risk is
inconvenience. It does not hold for these two, for different reasons:

1. **The Termii keys can spend money, and Termii is not being
   decommissioned.** It survives the migration by design (Phase 3), so
   "rotate when we switch off the old stack" never arrives for them. Anyone
   reading the public history can send SMS billed to you today.
2. **The Appwrite server keys** grant full access to the old project. That
   project is dormant, which lowers the impact — but it is the same tenancy
   the new project would live in.

Rewriting history does not help: the repositories are public and the commits
are long since cloned and indexed. **Assume both are known and rotate at the
vendor.** The old values keep working until you do.

Order: Termii first (money), then Appwrite. Neither needs a code change —
both are read from the environment.

## The decommission runbook, for when it is earned

Not before: a production migration completed, `reconcile.mjs` exiting `0`
against the real data, and push target registration climbing (Phase 3 —
OneSignal subscriptions cannot be transferred, so push reaches nobody until
each user opens the new build).

1. **Stop writes to Supabase**, keep it readable. Reversible.
2. **Run one week** on Appwrite with Supabase intact. The failure this
   guards against is the one Phase 6 names: an event Function that did not
   fire, leaving a report nobody was told about. A week of Supabase as a
   cross-check is cheap.
3. **Take a final export** and store it outside both vendors.
4. **Railway worker off** — its jobs are scheduled Functions by then.
5. **Resend and OneSignal off**, in that order. Email is recoverable if
   wrong; push silence is not noticed until it matters.
6. **Supabase project deleted last**, and only after the export is verified
   restorable, not merely taken.
7. **Rotate everything that remains** — Termii, ImageKit, the new Appwrite
   keys — and confirm no key is read from a file in either repository.

Step 6 is the only irreversible one. Everything above it can be undone in
minutes.

## Standing rule, earned twice over

Phase 7's reconciler read a `400` as "zero rows" and condemned a correct
migration. `browser-test.sh` exited `0` with twenty failing tests. This scan
reported three Termii keys and two were npm hashes.

**A checker may not treat a failed or ambiguous result as a finding, in
either direction.** Verify each hit before acting on it, and make the checker
fail loudly when it cannot tell.

## Not in scope here

The auth half of the client swap (Phase 2 maps it; Phase 5 explains why it
waits), and the production cutover and decommission themselves, which need
the Cloud project and a completed migration respectively.

---

# Phase 5b: the auth half of the client swap

Status: **built, in `main`-shaped code, and now under test**. 747 tests pass
(679 before, +68 new), `dart analyze` is clean, `dart format` is clean, and
no behaviour changed except one message, noted below.

Phase 5 deliberately stopped at the data layer and said why: `auth_provider.dart`
is the largest and most security-sensitive file in the app, and rewriting it
against an Appwrite the app cannot yet reach was not worth the risk. That
reasoning covered *rewriting* it. It did not cover *decoupling* it, which is
the part that is worth doing whether or not Appwrite ever happens.

## What the coupling was, precisely

116 references to `sb.User`, `sb.AuthException`, `sb.AuthState`,
`sb.OtpType`, `sb.UserAttributes` and `sb.AuthResponse` — and underneath
them, **nine `switch (e.code)` blocks branching on GoTrue's string error
codes**:

```dart
switch (e.code) {
  case 'over_email_send_rate_limit':
  case 'over_request_rate_limit':
    throw AuthException((l) => l.authErrorTooManyAttempts);
```

This is the same defect Phase 5 found in the data layer, in a different
dialect. `otp_expired`, `email_not_confirmed`, `over_sms_send_rate_limit`,
`bad_jwt` are GoTrue's vocabulary. Appwrite has none of them — it answers
with HTTP statuses and its own `type` strings. Left alone, every one of
those `switch` statements would fall through to `default` after the
migration, and the app would answer *"Registration failed. Please try
again."* to a user whose real problem is a rate limit, and *"Login failed"*
to one whose address is simply unconfirmed. Silently, and only in
production.

## The seam

`lib/core/services/auth_backend.dart` — an **interface**, not a registry.
That is the one structural difference from Phase 5: `backend_failure.dart`
is a set of pluggable functions because its call sites are pure functions
with nowhere to hold a service. The auth call sites all hold a reference
already, so an injected adapter is the honest seam.

Three types:

- **`AuthUser`** — `id`, `email`, `phone`, `emailConfirmedAt`,
  `phoneConfirmedAt`, `createdAt`, `metadata`. Everything here has a
  counterpart in both backends. What does not — GoTrue's `identities`,
  `appMetadata`, `aud` — stays inside the adapter.
- **`AuthChange`** / **`AuthEvent`** — the six session transitions the
  provider acts on. `AuthChange.user` is null exactly when there is no
  session, which is the only property of the session object the provider
  ever read.
- **`AuthFailure`** — fifteen conditions, one per *server condition* rather
  than per call site.

| `AuthFailure` | GoTrue today |
|---|---|
| `network` | `AuthRetryableFetchException` |
| `invalidCredentials` | `invalid_credentials`, `user_not_found` |
| `emailNotConfirmed` | `email_not_confirmed` |
| `accountExists` | `user_already_exists`, `email_exists`, `phone_exists` |
| `accountBanned` | `user_banned` |
| `invalidEmail` | `email_address_invalid`, `validation_failed` |
| `providerDisabled` | `signup_disabled`, `email_provider_disabled`, `phone_provider_disabled` |
| `deliveryFailed` | `sms_send_failed` |
| `otpDisabled` | `otp_disabled` |
| `rateLimited` | `over_email_send_rate_limit`, `over_sms_send_rate_limit`, `over_request_rate_limit` |
| `otpExpired` | `otp_expired` |
| `weakPassword` | `AuthWeakPasswordException`, `weak_password` |
| `samePassword` | `same_password` |
| `sessionExpired` | `session_not_found`, `bad_jwt` |
| `reauthenticationNeeded` | `reauthentication_needed` |
| `unknown` | anything else — never guessed at |

One condition, several sentences: `providerDisabled` means the same thing
during sign-up and during a phone OTP, but the user is told *"Registration
is currently disabled"* in one and *"SMS is unavailable"* in the other.
Choosing the sentence stays in the flow that knows the context; naming the
condition is the adapter's job. That split is what makes the table above
translatable to a backend with entirely different codes.

`AuthBackendException` carries the server's `code` and `message` too — for
the log line only. No control flow may read them, or the coupling returns
through the back door.

## Three things the move surfaced

**1. One Supabase behaviour is not an error and means the same as one.**
With email confirmations on, signing up with an address that is already
registered returns **200 and an obfuscated user with no identities** —
deliberately, so the response cannot be used to enumerate accounts. The
provider was reading `response.user?.identities` and inferring the refusal
itself. That is GoTrue trivia sitting in a registration flow; it now lives
in the adapter, which raises `accountExists` like any other refusal. Phase 2
notes that Appwrite answers a duplicate with a 409 instead — the provider
will not need to care.

**2. `reloadCurrentUser` was an auth call hiding in the data service.**
`SupabaseService.reloadCurrentUser()` is `GET /account` with extra steps,
and `ProfileProvider` depended on it. It is now `AuthBackend.reloadUser()`.

**3. The recovery `redirectTo` belongs to the adapter.** The fix we shipped
last month — `redirectTo: kIsWeb ? null : kPasswordResetRedirect`, so the
link opens the app rather than the admin portal — is a property of
*link-based* recovery. Phase 2's design has no link in it at all, so this
whole parameter disappears on Appwrite. Keeping it in the provider would
have made a Supabase workaround look like an app requirement. It is now
three lines inside `SupabaseAuthBackend.sendPasswordResetCode`, and the
Appwrite adapter will simply not have them.

## The one behaviour change

Sign-up had two near-identical messages for the same situation:
`authErrorEmailRegistered` ("Email is already registered") for the
obfuscated path and `authErrorAccountRegistered` ("This account is already
registered") for an explicit `email_exists`. The split was an artifact of
*how* the duplicate was detected, not of anything the user did differently.
Both paths now say "This account is already registered. Please login."
`authErrorEmailRegistered` is left in the five `.arb` files — removing it
churns every locale and the generated code for no benefit.

## Tests: the real payoff

68 new tests, and they cover ground that **had no test at all** before.

- `test/unit/auth_backend_test.dart` — all 23 GoTrue codes, both exception
  subtypes that outrank a code, the timestamp parsing (GoTrue returns these
  as strings, not `DateTime`), and the rule that an unrecognised code is
  `unknown` rather than guessed at.
- `test/unit/auth_provider_backend_test.dart` — a `_FakeAuthBackend` the
  tests steer, driving every refusal branch of sign-up, sign-in, OTP
  verification and both password-reset flows to the exact sentence the user
  sees.

None of this was reachable before: the flows went straight into
`supabase_flutter`, so the nine `switch` blocks that decide what a user is
told after a failed sign-in, a refused code or a password that will not set
were untested. They are the app's worst moments to get wrong.

Four of the new tests are not about wording at all, and matter more:

- a `verifyOTP` that answers with a user and **no session** must be refused,
  not treated as a sign-in;
- a sign-in whose outcome carries no user must not half-apply;
- a **refused** reset code must leave an existing session alone (the reset
  screen is reachable while signed in — a typo must not log the user out);
- an **accepted** reset code must always end in a sign-out, *including when
  the password change then fails*.

Each of those is a one-line regression away, and each would have been found
in production.

## Result

| | after Phase 5 | now |
|---|---|---|
| Files importing `supabase_flutter` | 4 | **2** — both adapters |
| Vendor auth types in feature code | 116 refs | **0** |
| `switch (e.code)` on GoTrue strings | 9 | **0** |
| Tests over the auth flows | 0 | **68** |

The two remaining importers are `supabase_service.dart` and
`supabase_auth_backend.dart`. Writing the Appwrite half is now writing two
files against two interfaces, not archaeology across the feature tree —
which is exactly what Phase 5 claimed the data seam was worth, now true of
auth as well.

## Still not done, and still deliberately

This decouples; it does not migrate. There is no `AppwriteAuthBackend`,
because there is still no Appwrite project to point one at — the region and
Cloud-quota questions from Phase 1 remain open, and this container cannot
reach Appwrite Cloud. When those are answered, Phase 2's call-by-call map
and this interface are the same list, in the same order.

---

# Phase 5c: the data half, and the four files that went around it

Status: **built, in `main`-shaped code**. 752 tests pass (747 before, +5),
`dart analyze` clean, `dart format` clean, no behaviour change.

## What was still wrong after 5 and 5b

Phase 5 took the engine's error codes out of feature code; Phase 5b did the
same for auth. Both left the same thing behind, and the number is the
tell:

- files importing `supabase_flutter`: **2** — correct, they are the adapters;
- files naming `SupabaseService` **by type**: **22**.

So the vocabulary was clean and the wiring was not. "Swap the backend"
still meant editing every provider, every admin screen and five core
services. A seam that only the error messages pass through is half a seam.

Worse, **four files reached straight past the service into the raw
PostgREST client**:

| | call | why |
|---|---|---|
| `reports_status_provider` | `client.rpc('reopen_report', …)` | no RPC on the service |
| `remote_config_service` | `client.from('app_settings').select('key, value')` | a two-column projection |
| `peer_verification_service` | `client.from(…).select('*, verifier:profiles!verifier_id(name)')` | a join |

Those are not stylistic. An RPC and a join are the two things Appwrite
*cannot do the same way at all* — Phase 4 turns the first into a Function
and Phase 1 denormalises the second — so they were exactly the calls that
had to be named before anything could be swapped, and exactly the ones
hidden from any audit that greps for `supabase_flutter`.

## The seam

`lib/core/services/data_backend.dart` — `DataBackend`, the documents,
realtime and files surface, implemented by `SupabaseService` today.
Nothing in it is Postgres-shaped. Two operations earned explicit names:

**`callOperation(name, params)`** — a named server-side operation. Postgres:
a `SECURITY DEFINER` function over RPC. Appwrite: a Function execution,
which is where Phase 4 already puts every guarded write.

**`RelatedFields`** — fields pulled in from a related collection, and the
only place in this interface with a deliberate *best-effort* contract:

> An adapter that cannot honour this must return the plain documents rather
> than fail.

Postgres does it as a PostgREST embed — one round trip, under the same RLS
as the base rows. Appwrite cannot join at all. Phase 1 denormalises the one
field this app embeds, and until then the fallback is the behaviour the
call site already had: a verification whose verifier profile is unreadable
shows no name. The retry-on-failure that used to sit in
`peer_verification_service` now sits in the adapter, where the contract is
written down.

`lib/core/services/backend.dart` is the composition root — a plain locator
(`backend`, `authBackend`, `initializeBackend`) and **the only file in the
app that names a vendor**. It re-exports `DataBackend`, `AuthBackend`, the
query vocabulary and the failure vocabulary, so a caller needs one import
and names no backend to read a document, build a filter or ask why a write
was refused.

## Three things the move surfaced

**1. The three refusal predicates never got converted.** `backend_failure.dart`
has had `BackendFailure.refused`, `.duplicate` and `.rateLimited` since
Phase 5, and eight call sites were still asking the Supabase adapter
directly — `SupabaseService.isPermissionDenied(e)`. They are now
`isRefusal(e)`, `isDuplicate(e)`, `isRateLimited(e)` on the vocabulary
itself. The mapping is identical, code for code; it just stops naming the
engine.

**2. `ReportVerification.fromRow` read column names.** `verifier_id`,
`is_confirmed`, `submitted_at` — snake_case is Postgres's convention, and
the mapping layer had already been normalising every other read to
camelCase for a year. It is `fromDocument` now and reads fields.

**3. Two exceptions and one were in the wrong file.**
`DocumentNotFoundException`, `BackendNotConfiguredException` and
`ImageEncodingException` are thrown at six feature call sites and say
nothing about Postgres. They lived in `supabase_service.dart`, so catching
"this document is gone" meant importing the vendor's adapter. They are in
`data_backend.dart` now.

## The two changes that were reasoning, not observation — and how they were checked

Replacing a hand-written PostgREST string with a generated one is the kind
of change that passes every test and fails in production, because the
server parses the string and the client never validates it. A typo in the
embed does not throw at the call site: it throws inside the adapter, hits
the best-effort fallback **by design**, and every verifier name quietly
disappears from the UI with nothing logged as an error.

So both were verified against the real mapping layer rather than argued
from the code:

```
users    -> profiles          fk    -> verifier_id
verif    -> verifications     field -> name
filters  -> [report_id]       orders -> [submitted_at asc=false]   limit -> 200
```

which makes the generated projection `*, verifier:profiles!verifier_id(name)`
— byte-for-byte the string that was there before — and the query plan
identical to the `.eq().order().limit()` chain it replaced. Both are now
pinned by tests in `test/unit/data_backend_test.dart`, along with the
`app_settings` read, where the mapper adds `$id`/`id` keys that the caller
happens not to iterate.

That is the standing rule from Phase 7 applied before the fact rather than
after: **a check that cannot fail is not a check.** A silent degradation
needs a test that fails loudly, because nothing else will.

## Result

| | after Phase 5b | now |
|---|---|---|
| Files importing `supabase_flutter` | 2 | 2 — the adapters |
| Files naming `SupabaseService` in code | 22 | **1** — the composition root |
| Feature code reaching the raw client | 4 | **0** |
| Vendor types in test fakes | 3 | **0** |

`chat_screen` is worth a line of its own, since it had the last of both
problems: it held a `SupabaseService` field *and* built its own
`SupabaseAuthBackend()` to ask who was signed in — a second source of
session truth inside a widget. It reads `AuthProvider` now, like every
other screen.

## What this does and does not buy

Writing the Appwrite half is now: implement two interfaces, change three
lines in `backend.dart`. It is not a pass over the feature tree, and the
compiler finds everything.

It buys nothing on the questions that actually gate the migration — the
Cloud **region** against the NDPA residency position, and the **tier
quotas** for 584 teams and more than one bucket. Those have been open since
Phase 1 and no amount of client refactoring closes them.

---

# Phase 9: the Appwrite adapters

Status: **written, analysed, formatted, and tested where testing is
possible without a server.** 817 tests pass (752 before, +65). Nothing here
has been run against Appwrite — there is still no project to point it at —
and that limit is stated again at the end rather than buried.

## What exists

| file | what |
|---|---|
| `appwrite_config.dart` | endpoint, project, database, the three Function ids, and the write policy |
| `appwrite_queries.dart` | `QueryFilter` → Appwrite queries, and `DocumentPlan` for the client-side half of a stream |
| `appwrite_documents.dart` | row ↔ app document |
| `appwrite_errors.dart` | Appwrite's refusals in both vocabularies |
| `appwrite_data_backend.dart` | `DataBackend` |
| `appwrite_auth_backend.dart` | `AuthBackend` |
| `backend.dart` | picks one, by which credentials the build was given |

`docs/APPWRITE-FUNCTION-CONTRACTS.md` is the other half: the three
Functions these adapters call, specified from what Phases 1–4 proved and
what the client now actually sends.

## A correction, immediately

Earlier in this phase I checked whether Appwrite's document API was
deprecated, read the class header and the one deprecated method on it, and
said it was fine. It is not: **the whole `Databases` service is deprecated
as of Appwrite 1.8 in favour of `TablesDB`** — `createRow`, `listRows`,
`upsertRow`. The analyzer said so the moment the first draft compiled.

That matters beyond tidiness. The spike ran against self-hosted **1.6.2**,
which has no `TablesDB` at all; Cloud — the chosen target — is well past
1.8. The adapter uses `TablesDB`, so it will not run against the spike's
own server. Anyone re-running the spike to check something should expect
that.

It also gained something: `TablesDB` has a native `upsertRow`, so the
upsert is one call rather than create-catch-409-then-update.

## Four decisions worth stating

**1. The write policy is a list of what the client *may* write.**
`AppwriteConfig.clientWritableCollections` names five collections —
contacts, messages, trusted devices, login history, NDPA consents.
Everything else goes through the `write` Function. The list is that way
round on purpose: a collection added later and forgotten defaults to the
Function, which fails safe. The other way round it would default to a
direct write the server then has to refuse, and the bug would be a
production 401 rather than an extra round trip.

**2. Redeeming a typed code happens server-side, to keep enumeration
shut.** `account.createSession` needs a `userId`; the client has only the
address the user typed. Handing out a `userId` in exchange for an address
is an enumeration oracle, and Phase 2 lists preserving Appwrite's silence
there as a requirement. So the Function takes address *and* code together,
resolves the user itself, redeems the token and returns a session secret
for `Client.setSession`. Unknown address and wrong code answer identically.

**3. Appwrite signs unverified accounts in; GoTrue refuses them.** The
app's login screen *depends* on the refusal — it is what sends the user to
the code screen with a fresh code. So the adapter checks
`emailVerification` after a successful sign-in, **signs the session back
out**, and raises `emailNotConfirmed`. Without that, an unverified account
would land on the dashboard.

**4. `updateEmail` now takes a password, because Appwrite demands one.**
Supabase does not. Rather than let it fail with a bare 401, the adapter
raises `reauthenticationNeeded` when no password is given — a condition
`ProfileProvider` already has wording for ("please sign in again to change
your email"). The UI change that would collect the password is a known
follow-up, not a surprise.

## The defect the tests found, and the test that nearly missed it

Appwrite addresses files by **id**, capped at 36 characters, not by path.
The app's paths are `<userId>/report_<timestamp>.jpg` — 60 characters with
a UUID. The obvious translation is to keep the last 36.

That is wrong, and quietly. The filename alone is 24 characters, so
truncation keeps the whole filename and only a 12-character tail of the
user id. Two agents whose ids end alike, photographing the same hazard in
the same millisecond, get the same file id — and **the second upload
overwrites the first's evidence**, with no error raised anywhere.

The test written for it first was
`'two different paths do not collide on their tail alone'`, comparing
`u1/report_1.jpg` with `u2/report_1.jpg`. Both are 15 characters. Neither
is truncated. The test passed because the code path it was meant to
exercise never ran — the same shape of failure as `browser-test.sh`
exiting 0 with 20 failures, and the reconciler reading a 400 as zero rows.

The id is now a 19-character readable prefix plus a 64-bit FNV-1a digest of
the whole path, and the tests use realistic 60-character paths plus a
3,600-path batch that asserts 3,600 distinct ids.

**A check that cannot fail is not a check.** Third time; it is in the doc
twice already and it still nearly got through.

## What is tested, and what cannot be

Tested, 65 new cases:

- **every filter translation**, with the null semantics made explicit on
  both sides. `notEqual` is written as *not null and not equal* and
  `distinctFrom` as *null or not equal*, so neither depends on how
  Appwrite resolves a bare `notEqual` — which is not documented and has
  not been observed here. An empty `IN` is a contradiction rather than an
  empty `equal`, because an empty `equal` would read as *no constraint*
  and return the whole collection.
- **the whole error table**, both vocabularies, including the invariant
  that nothing is classified both transient and permanent, and that a bare
  400 is neither.
- **the document mapping**, including that a collection's own `createdAt`
  is never overwritten by Appwrite's `$createdAt` — `reports.createdAt` is
  when the hazard was seen, not when the row was written, and an offline
  report submitted days later would otherwise carry the wrong date with
  nothing flagging it.
- **file ids**, as above.

Not tested, because it needs a server: every call. Sign-in, the Function
exchange, realtime, uploads, the session restore. The error slugs are from
Appwrite's published list and an unlisted one falls through to `unknown`,
which is the safe direction — a generic message rather than a confidently
wrong one — but *which* slugs a given endpoint actually returns is an
observation nobody has made here.

## Still blocking, now for the ninth phase running

The adapters do not make the region question or the quota question any
smaller, and they are the only two things standing between this and a
migration:

1. **Which Cloud region** is lawful under the NDPA. The old project was
   Frankfurt. If in-country residency is required, Cloud is out and the
   whole plan moves to self-hosting — which changes Phases 2, 4 and 6
   materially.
2. **Whether the tier allows** 584 teams, ~650 messaging topics and more
   than one storage bucket.

This container cannot reach `appwrite.io`; the egress proxy refuses it. One
answer to each, or a set of Cloud credentials and proxy access, and the
next step is deploying the three Functions and running the adapters against
them.

---

# Phase 10: the three Functions

Status: **written and tested against a fake Appwrite.** 63 Node tests,
plus 819 Dart (up from 817). `dart analyze` and `dart format` clean, and a
CI job runs the Node suite on every push. Nothing has met a real server.

`functions/cradi/` — three Functions, one source tree, because Appwrite
lets several Functions share a root directory and differ only by
entrypoint. The helpers in `src/lib/` therefore exist once instead of
three times, which matters more than it sounds: `wardTeam` drifting
between copies is the failure mode described below.

**No dependencies, deliberately.** `src/lib/appwrite.js` calls the REST
API over `fetch` rather than using the Node SDK. Phase 4 measured a 735 ms
cold start on an idle local box with no network in the way; on a quiet
night in a quiet ward the first report of the morning pays it, and every
dependency is paid again on every cold start.

## The defect this phase existed to find

`wardTeam` is a pure function of state, LGA and ward, and Phase 0's whole
finding rests on it: document ACLs name the **team**, so moving an agent
between wards is a membership change rather than a rewrite of every
document they can see.

Writing a test over all 584 wards rather than the three in the examples
showed that **35 of them produce a team id longer than Appwrite's
36-character limit**:

```
ward-plateau-langtang-north-langtang-north-central   50
ward-nasarawa-nasarawa-egon-lizzin-keffi-ezzen       46
ward-nasarawa-nasarawa-egon-igga-burumburum          43
```

Appwrite rejects those outright. The failure would have surfaced in
production, for 6% of the country, only once somebody filed the first
report in one of those wards — and the spike never touched one, because
its fixtures were all in Makurdi.

The id is now the plain slug where it fits and a truncated slug plus a
64-bit digest where it does not, so **the 549 that already fit are
unchanged** and nothing designed around them moves. All 584 are checked
for length and for uniqueness.

`migrate/migrate.mjs` had its own copy of `wardTeam`, with the same bug.
It now imports this one. A copy was never defensible here: one character
of drift between the two means every migrated document points at a team
nobody is in, the whole ward sees nothing, and no error is raised
anywhere.

## Three things the client could not have told us

**1. The spike trusted the request body for the caller's identity.**
`create-report` read `req.headers['x-appwrite-user-id'] || payload.userId`.
The fallback is fine for a spike and is a hole in production: the body is
entirely under the client's control, so it hands any caller the ability to
act as anyone — which is the one thing moving these writes into a Function
was for. The header is the only source now, and a test asserts it.

**2. A refused field has to be refused, not ignored.** A user sending
`isApproved: true` on their own profile gets a 403 naming the field. The
tempting alternative — strip it and answer 200 — tells somebody their
request succeeded when it did not. The rule differs by kind, and the
difference is written down: fields the server *owns* (a report's `status`)
are silently overwritten, because a well-behaved client round-tripping a
document it read would otherwise break for no gain; fields the caller is
*not allowed to set* are refused.

**3. Appwrite has no transactions, so `reopen_report` has an order.**
Clearing the votes before reopening means an interrupted run leaves a
closed report with some votes gone, which running it again fixes. The
other order leaves a reopened report carrying stale votes, and it
re-escalates immediately on a count that is no longer true. The test
asserts the order, not just the outcome.

## What the tests cover

63 cases, no server and no network: `test/helpers.mjs` stubs the single
`fetch` every call goes through, which is enough to drive a whole handler.
They are aimed at what the server stores regardless of what the client
sent:

- Phase 4's third row, now a test: a client sending
  `status:"approved", verificationCount:99, escalated:true` gets a success
  and a stored document that says `pending`, `0`, `false`;
- the caller comes from the header, never the body;
- a vote takes its ward from the **report**, so an EWM cannot vote on
  another ward's report by claiming it is theirs — the cross-collection
  check the old `verifications_insert` policy made;
- a disabled account is refused in words the user will see, because a 4xx
  with no error slug is exactly what the client shows verbatim;
- recovery answers **identically** for an address with no account, and
  mints nothing;
- a wrong code and an unknown address are indistinguishable;
- the ward team exists before the document whose ACL names it, or nobody
  in the ward can read it;
- `reopen_report` is refused for a role that may not run it, and nothing
  is touched on the way to the refusal.

Two more guard the seams rather than the behaviour: `serverOwned` must
list exactly what `create()` stamps, and a collection may not be both
client-writable and Function-written — two write paths with two sets of
rules is how a rule gets enforced in one and not the other.

## Still not run against Appwrite

Everything above runs against a fake that behaves the way these Functions
assume Appwrite behaves. The assumptions are drawn from Phases 0–4, which
*were* executed — against 1.6.2, which has no `TablesDB`, so the adapters
and these Functions cannot be re-checked against that spike either.

What remains unverified: that `POST /account/sessions/token` with a server
key returns a usable `secret` (Phase 2 verified the client-side half of
this sequence, not the server-key form); that Appwrite Messaging delivers
with our own template; that the scopes listed in the README are the right
set; and the cold-start cost of three Functions on Cloud rather than one
on a local box.

And the two questions from Phase 1, now ten phases old: **which Cloud
region** is lawful under the NDPA, and **whether the tier allows** 584
teams, ~650 topics and more than one bucket.

---

# Phase 11: the worker

Status: **written and tested against a fake.** 107 Node tests (63 before,
+44), 819 Dart, analyze and format clean. Still nothing against a real
Appwrite.

Four Functions, nobody calls them: `on-write` (document events), `drain`
and `escalate` (every minute), `reconcile` (every five). Together they
replace the Railway service — its outbox loop, its escalation cron, and
the OneSignal, Resend and Termii calls underneath.

## The shape Phase 6 forced

Phase 6 established by experiment that an event Function runs **once** and
is never retried. That is the load-bearing fact, and it shows up in three
decisions here:

**`on-write` does one write and nothing else.** Everything an event
Function does is work that can silently not happen, so it writes one
outbox document and leaves delivery to a schedule, which *is* retried.

**The escalation row is written by `write`, not by an event.** A Postgres
trigger created it in the report's transaction. Putting it in the event
Function would have been tidier and would have meant that, whenever that
Function failed, a report quietly never escalated. It is one more
non-transactional call inside the write instead — a failure there fails
the write and the client retries, which is the better failure.

**`reconcile` exists at all.** Phase 6 called the lost transactionality
"the loss that has no clean mitigation" and said the honest answer was a
reconciling sweep. This is it, and it is as imperfect as predicted: it
catches creates but not missed status changes, its 20-minute window is a
guess, and the only exact thing about it is that it cannot double-notify,
because outbox ids are deterministic and a re-enqueue collides with 409.

## Two defects the tests found

**An edit re-announced the report.** Appwrite's event payload is the
document, not the change, so `on-write` cannot see a status transition.
The `write` Function stamps `previousStatus`, and the first version read
`doc.previousStatus ?? null` — which meant a description fix, with no
`previousStatus` at all, produced a `report_status_changed` from `null`
to the unchanged status. The handler's staleness check would have passed
(the status *does* match) and every reporter would have been re-notified
on every edit of their report. The absence of the field now means "this
edit did not touch the status", which is what it actually means.

**Outbox ids collided across event types.** `eventId` trimmed to the last
36 characters, and a uuid key is already 36 — so `report_created-<uuid>`
and `report_disputed-<uuid>` both became the bare uuid. The second event
on a report would have been swallowed as a duplicate of the first: a
dispute on a report that had already been created would simply never
notify anybody. Same class as the file-id defect in Phase 9 and the ward
team id in Phase 10; the fix is the same readable-prefix-plus-digest.

Three occurrences of one mistake — *an id that is a truncation is not an
id* — is enough to call it a pattern rather than three accidents.

## What the fake does and does not prove

`test/helpers.mjs` stubs the single `fetch` every call goes through. One
thing in it is worth naming: **it refuses a duplicate `messageId` with
409**, exactly as Appwrite does. Without that the idempotency tests would
all pass vacuously, which is the failure mode this document has now
recorded four times. With it, the "two overlapping drains cannot
double-send" test actually exercises the property the whole claim-free
design rests on.

What it cannot prove is that Appwrite behaves that way. Phase 3 verified
the 409 against a running 1.6.2 and Phase 6 verified the deterministic-id
claim; neither has been re-checked on Cloud, and Cloud is past 1.8 where
the document API these were tested through is deprecated.

Also unverified: that Appwrite Messaging push reaches a device with the
topics Phase 3 designed, that `targets.read` is the right scope for
sending to users, that a one-minute schedule is honoured under load, and
Termii's behaviour on anything but the happy path.

## What is left before this can run

Nothing in the client, the Functions, or the worker is now missing. What
is missing is a place to put it:

1. **The Cloud region**, against the NDPA residency position.
2. **The tier quotas** — 584 teams, ~650 topics, more than one bucket.

Eleven phases, and those two have been open since the first.

---

# Phase 12: provisioning

Status: **written; not run against a project, because there is no route
to one from here.** The environment's network policy answers 403 at the
gateway for `cloud.appwrite.io`, `fra.cloud.appwrite.io` and
`appwrite.io`. 116 Node tests (107 before, +9), 819 Dart, clean.

`infra/appwrite/` turns "set up the project" into one idempotent command.

| | |
|---|---|
| `extract-schema.mjs` | derives the Appwrite columns from `supabase/migrations/` |
| `columns.json` | the generated output, committed |
| `plan.mjs` | the declared target: 19 collections, 187 columns, 2 buckets, 7 Functions |
| `provision.mjs` | makes a project match it — `--dry-run` works offline |
| `verify.mjs` | read-only; reports where a live project differs |

A dry run prints **237 objects**.

## The columns are generated, and that is the point

Hand-writing 19 collections' worth of columns would have been faster and
would have created a second source of truth for a schema that already has
one. `supabase/migrations/` *is* the live database. So the extractor
reads it, maps Postgres types onto Appwrite's five, converts snake_case
to the camelCase the app uses, and a test fails when the committed file
falls behind.

The failure that avoids is specific: a column added to Postgres and
forgotten here is a write the server rejects — in production, with the
field agent's report already typed in. As a red CI run it costs a minute.

## Three things the provisioner refuses to do

**It never deletes.** A column in the project that is not in the plan is
printed with a `?` and left alone. Dropping a column drops its data, and
this will be run against a project holding live reports. A provisioner
that converges by deletion is a provisioner that eventually deletes
something it should not.

**It stops on a quota refusal** rather than carrying on. Everything after
the first `402` would fail the same way and bury the reason in two
hundred lines. It says plainly that this is the tier question the doc has
been asking since Phase 1 — so running it is also how that question gets
answered, if the pricing page cannot.

**It does not exit 0 on failure.** Stated because this project shipped a
checker that reported success over twenty failures, and a reconciler that
read a `400` as "zero rows". The verifier is written the same way: an
unreadable project is a *failure*, not an empty diff, and it checks three
states a bare existence check calls fine — a column stuck in `processing`
(present, rejects every write), a Function created but never deployed
(500s on every call, looks healthy in the console), and a schedule that
silently does not match.

## The region, settled

**Frankfurt.** `https://fra.cloud.appwrite.io/v1`, now the default
throughout `infra/appwrite/`.

Chosen on latency — of the Appwrite Cloud regions, Frankfurt is much the
closest to Nigeria (Lagos–Frankfurt ≈ 4,500 km against ≈ 8,500 km to New
York) — and it is where the previous project ran. The owner's decision,
2026-10-02, is that NDPA in-country residency is not a constraint on this
deployment. Recorded here because the alternative was a data-residency
position on real people's hazard reports, locations and phone numbers,
and because the choice cannot be revisited later without migrating
everything a second time.

This closes the question that had been open since Phase 1.

## One quota answer, from the project's own history

The other open question was the tier. Part of it is already answered, and
not from a pricing page — from the previous Appwrite project's committed
config:

> Due to Appwrite free tier limits (max 1 bucket), Profile Photos and
> Report Images currently share the same bucket but are logically
> separated by folder paths.

So the tier that project ran on allows **one** bucket, and Phase 3's
design wants two with different ACLs. `provision.mjs --single-bucket`
provisions one instead, and the app's bucket ids became
`String.fromEnvironment` so the same code works either way.

That is not a security compromise **provided `fileSecurity` stays on**:
with per-file ACLs, evidence still carries its ward-team reads and a
profile image still carries `read("any")`. A file written with no
permissions falls back to the bucket's, which grant no reads — so the
failure mode is a file nobody can see rather than one everybody can. What
it costs is independent retention and deletion, and the fact that a bug
in the evidence path now writes into the same bucket as avatars.

## The provisioner ran, and refused at the first step

The owner ran it against the existing Frankfurt project. It got exactly
as far as the first object and stopped, which is what it is for:

```
# https://fra.cloud.appwrite.io/v1 project 6941cdb400050e7249d5

! stopped at database cradi: the project's plan refused it.
  The maximum number of databases allowed for the selected plan has reached.
```

**The plan allows one database**, and the project already has one — the
old Appwrite build's, `6941e2c2003705bb5a25`. Not fatal: the plan's
database id is already `process.env.APPWRITE_DATABASE_ID ?? 'cradi'`, so
provisioning into the existing one is a variable, not a change.

Two things this run established beyond the limit itself. The endpoint,
the project id and the key all work — this is the first contact anything
in twelve phases has made with a real Appwrite — and the stop-and-name
behaviour earned its keep immediately, because the message is the whole
answer and would have been the first of two hundred lines otherwise.

## `--probe`, because each limit was costing a round trip

Stopping is right for a real provisioning run. It is wrong when the
question *is* what the plan allows, because then every limit costs a
full round trip to discover — and this one is being discovered by a
person pasting output back.

So `--probe` keeps going past quota refusals and lists every one at the
end. It also creates a single throwaway team and topic, and deletes
them: those are the two quotas no pricing page states plainly, and the
two Phase 0 and Phase 3 cannot do without. It does not create 584 of
anything.

## The answer, after twelve phases: not on this plan

`--probe` run against the existing Frankfurt project, 2026-10-02. The
plan refuses, in order:

| | What it said |
|---|---|
| **Databases** | `The maximum number of databases allowed for the selected plan has reached.` The project's one slot is taken by the old build. |
| **Functions** | `The maximum number of functions allowed for the selected plan has reached.` **All seven refused.** |
| **Buckets** | `The maximum number of buckets allowed for the selected plan has reached.` Both refused. |
| **Columns** | `The maximum number or size of columns for table '<x>' has been reached.` Hit on `reports`, `alerts`, `authorities`, `contacts`, `ndpa_consents`, `knowledge_base`, `news_links`, `sms_deliveries` and both quarantine tables. |

**The Functions row ends the question.** This is not a quota to design
around. Phase 1 found 14 of 19 collections have a rule an ACL cannot
express, so every report, vote, alert and profile change is a Function
call; Phase 2 puts token minting in one because the API key cannot ship
in the app; Phases 10 and 11 put the entire worker in four more. Zero
Functions means no reports, no registration, and no warnings. There is
no reduced version of this design that fits.

The buckets row kills the mitigation too: `--single-bucket` was written
on the evidence that the old project ran on one, but the plan allows no
*new* bucket at all, so even one is unavailable without freeing the
existing one.

The columns row is the mildest and still real: `reports` alone needs 37.

### What this does and does not mean

It does **not** mean Appwrite is the wrong choice. Everything Phases 0–6
proved about the design — ward teams as ACL subjects, typed-code auth,
message idempotency, the deterministic-id lock — was proved against a
real Appwrite and still holds.

It means the **free plan cannot host it**, which is a billing decision,
not an engineering one. Two routes:

1. **A paid Cloud plan.** Needs enough Functions (7), buckets (1–2),
   databases (1 free slot, or delete the old one), and the per-table
   column cap lifted above 37. Teams and topics still need checking at
   584 and ~650.
2. **Self-hosting**, which has no quotas at all — and brings back every
   operational trap Phase 4 recorded, plus the ones Phase 6 found for
   scheduled Functions. The region question would reopen as a server
   choice.

### Two things that were cheap and paid off here

The provisioner names a quota refusal rather than reporting it as a
generic failure, and `--probe` collects every one in a single run. The
alternative — discovering four limits one round trip at a time, each
costing a person a paste — would have taken this conversation four more
exchanges to reach the same conclusion.

And it never deletes. Pointed at a project holding the old build, it
created what it could, reported what it could not, and left everything
else untouched.

## What is left

Twelve phases, and everything that can be built without a live project is
built: the client adapters, the three Functions the client calls, the four
that replace the worker, the migration pipeline, and the provisioning.

What remains is not design work. It needs a project, a fresh server key —
two from the previous project are in public git history — and a route to
`fra.cloud.appwrite.io`, which this container does not have: the
environment's network policy answers 403 at the gateway for it, for
`cloud.appwrite.io` and for `appwrite.io`.


---

# Phase 13: a real Appwrite, locally — and three bugs that were mine

Status: **the whole project provisions clean against Appwrite 1.8.0.**
`created=11 exists=228 failed=0`, 239 objects, all seven Functions, both
buckets, and the independent verifier agrees. Nothing is deployed yet.

The Cloud plan will not host this (Phase 12), but self-hosted has no
quotas — so the question "does any of this actually work" could be
answered before spending money, and it needed to be: Phases 9 to 12
wrote roughly two thousand lines that had never met a server.

`infra/appwrite/local/` is the stack. It is the Phase 4 spike's compose
at 1.8.0 with executor 0.7.22, carrying all four of that phase's traps
forward intact, on ports 8090/8091 so the 1.6.2 spike keeps running
beside it — that one still holds the Phase 0 to 6 proofs and tearing it
down to reuse a port would have been the Phase 4 mistake twice.

## Three bugs, and two of them were being blamed on the tier

**1. Column sizes, which Phase 12 misattributed.** The first local run
died at the fourth column of the first collection:

```
! stopped at profiles.email: The maximum number or size of columns
  for this table has been reached.
```

Not a quota. Appwrite stores a sized string as a MariaDB `VARCHAR`, and
**MariaDB caps a row at 65,535 bytes** — four per character under
utf8mb4. My extractor gave every unsized Postgres `text` a generous 8192
characters, which is 32KB of row budget each, so four of them filled it.

That message is word-for-word what Cloud returned for ten collections,
which means **Phase 12 blamed the tier for my bug**. The real Cloud
limits are databases, functions and buckets; the column failures were
mine. Corrected above.

The sizes are now small for ordinary fields and large for long ones,
because the middle is the expensive place to be: above ~16,000
characters Appwrite switches to `TEXT`, stored off-row at almost no
cost. `reports` went from refusing its fourth column to 42KB of a 64KB
budget across 37.

**2. `double` is `float`.** The route is `/columns/float`; the plan said
`double`, which is the Postgres name. A 404 reading "Route not found",
naming neither the column nor the reason.

**3. Function events are rooted at `databases`, not `tablesdb`.** This
one was not guessable. Realtime *channels* are
`tablesdb.<db>.tables.<t>.rows` — the Flutter SDK's own channel builder
produces exactly that, which is why Phase 11 used it — but Function
*events* are `databases.<db>.tables.<t>.rows.*.create`. Two namespaces
for the same objects, and only `app/config/events.php` inside the server
image says so.

A 400 at provisioning time is the good failure here. The bad one was
available: an event name that is merely *unmatched* rather than invalid
would have subscribed `on-write` to nothing, and the first anyone would
know is a hazard report that never notified a verifier.

## What the run settles

- **Teams and topics are accepted.** Both probes created and deleted
  cleanly. Open since Phase 1, and the answer on self-hosted is yes.
  Cloud's per-plan ceiling at 584 and ~650 is still unmeasured.
- **The provisioner is idempotent in practice, not just by design** —
  the second run reported `exists=228` and created only the 11 objects
  the fixes added.
- **The verifier fails when it should.** It found all seven Functions
  created but never deployed, which is the state that answers every call
  with a 500 and looks healthy in the console, and it exited 1.

## Not yet done

The Function code is not pushed, so nothing has been *executed* — only
created. That is the next thing, and it is what turns 116 tests against
a fake into evidence.
