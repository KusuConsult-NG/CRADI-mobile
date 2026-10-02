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

## Not in scope here

The client data-layer swap (Phase 5), the worker's outbox and escalation jobs
(Phase 6), and data migration and cutover (Phase 7).
