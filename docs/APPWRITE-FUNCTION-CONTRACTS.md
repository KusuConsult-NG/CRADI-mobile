# The three routes the client adapters call

The Appwrite adapters in `lib/core/services/appwrite/` are written against
these three contracts, derived from what Phases 1–4 proved and from what
the client now actually sends.

They were three Functions. The Cloud plan allows **two Functions in
total** against the seven this backend needs (3 October 2026; see
`CLOUD-VERIFICATION.md`), so they are now three routes of one —
`AppwriteConfig.clientFunctionId`, default `client`, entrypoint
`functions/cradi/src/client.js`. Which route runs is the **execution's
path**, passed as `path` on `createExecution` and read as `req.path`:

| contract | path | module |
| --- | --- | --- |
| 1. write | `/write` | `src/write.js` |
| 2. auth | `/auth` | `src/auth.js` |
| 3. operation | `/operation` | `src/operation.js` |

Nothing about the three contracts changed in the merge — each module is
still a complete handler and still writes its own response. A path the
router does not know answers `404 general_route_not_found` naming itself,
rather than Appwrite's own 404 naming a Function that no longer exists.

The merged Function is `execute: ['any']`, because `/auth` must be
reachable before there is a session. `/write` and `/operation` call
`callerId(req)` first, which reads `x-appwrite-user-id` — a header only
Appwrite sets — so a guest reaching them still gets the 401 it always
got, from the handler rather than from the platform.

Every route:

- is invoked with `POST`, `content-type: application/json`, synchronously;
- answers JSON;
- signals refusal with a **4xx inside a completed execution**, because that
  is what the client reads. The adapters turn
  `{status, body.type, body.message}` back into an `AppwriteException` so a
  Function refusal and an API refusal arrive at the app as the same thing;
- uses Appwrite's own [error type slugs](https://appwrite.io/docs/response-codes#errorTypes)
  in `body.type` where one fits. The client's error table reads `type`
  first and the status second; an unrecognised slug falls through to
  `unknown`, which shows a generic message rather than a wrong specific
  one.

An execution that never completes (cold-start timeout, crash) has no
response. The adapters treat that as a transport failure, **not** as a
refusal — a registration that timed out must not read as "email already
taken".

---

## 1. `/write` — the collections the client may not write

`AppwriteConfig.writePath`, `/write`.

Phase 1 found 14 of 19 collections have a rule an ACL cannot express.
Phase 4 proved the shape with `create-report`; this is its generalisation.

**Request**

```json
{ "op": "create" | "upsert" | "update" | "delete",
  "collection": "reports",
  "documentId": "<id the client generated, or a server one>",
  "data": { ... } }
```

`data` never contains `$id`, `id`, `$createdAt`, `$updatedAt` or
`$permissions` — the client strips them.

**Response** `200`/`201` with `{"document": { ...the stored row... }}`,
including `$id`, `$createdAt`, `$updatedAt`. A `delete` may answer with no
document; **any other op that does is a contract violation** and the client
raises rather than reporting a successful write of nothing.

**What it must enforce**, per Phase 4's proof:

- read the caller's profile; refuse a disabled account (`403`);
- **overwrite** every field the client must not choose — `status`,
  `verificationCount`, `escalated`, `userId`, `userName`, `userRole`. Phase
  4's third row is the one that matters: a client sending
  `status:"approved", verificationCount:99` got `201` and a stored document
  still reading `status: "pending"`;
- resolve the ward to a team id and set the document ACL Phase 0 designed;
- validate `state`/`lga`/`ward` against the bundled location list, which is
  what replaces the two dropped foreign-key tables.

**Refusals the client already understands**

| condition | status | `type` |
|---|---|---|
| account disabled, or role not allowed | `403` | *(none — the message is shown to the user)* |
| replay of a write that already landed | `409` | `document_already_exists` |
| the document is gone | `404` | `document_not_found` |
| a field failed validation | `400` | `document_invalid_structure` |

A bare `400` with no `type` is deliberately **not** read as a permanent
failure: Appwrite uses it for malformed requests too, and treating a client
bug as a permanent refusal would drop a field agent's queued report instead
of retrying it after the fix.

---

## 2. `/auth` — everything that needs a server API key

`AppwriteConfig.authPath`, `/auth`.

**Request** `{"action": "...", ...}`.

The design rests on the endpoint Phase 2 verified:
`POST /v1/users/{userId}/tokens {"length": 6, "expire": 900}` mints a
secret of **any length we choose**, so the app's six-digit code screens
survive instead of becoming email links. That call needs a server key, so
every step that touches it is here.

### `signUp`

```json
{ "action": "signUp", "email": "...", "password": "...",
  "metadata": { "name": "...", "role": "...", "phone": "...",
                "state": "...", "lga": "...", "ward": "...",
                "address": "..." } }
```

Creates the account, writes the `profiles` document from `metadata` —
**`role` is a request, not a grant; `isApproved` starts false** — mints a
6-digit token and sends the mail. Answers `200` with no session: the user
types the code next.

Duplicate address → `409` / `user_already_exists`.

### `resendSignUpCode`

`{"action": "resendSignUpCode", "email": "..."}` → a fresh token and mail.

### `sendRecoveryCode`

`{"action": "sendRecoveryCode", "email": "..."}`

**Must answer identically for an address that does not exist.** Appwrite's
own recovery endpoint deliberately does not reveal whether an account
exists and Phase 2 lists preserving that as a requirement. Mint nothing,
send nothing, return the same `200` and the same body. Timing should not
give it away either.

This is also where the per-address throttle lives — it was a Supabase
dashboard setting and is now our code.

### `verifySignUp` / `verifyRecovery`

```json
{ "action": "verifySignUp", "email": "...", "code": "251152" }
```

**Why the Function does the exchange rather than the client.**
`account.createSession` needs a `userId`, and the client only has the
address the user typed. Handing a client a `userId` in exchange for an
address is an account-enumeration oracle. So the Function takes the address
*and* the code together, resolves the user itself, redeems the token, and
returns the session:

```json
{ "sessionSecret": "..." }
```

The client calls `Client.setSession` with it. An unknown address and a
wrong code must be answered identically: `401` / `user_invalid_token`.

`verifySignUp` additionally sets `emailVerification: true`
(`PATCH /users/{id}/verification`). `verifyRecovery` does not — the session
it returns is only good for the password change that follows, and the
client signs out afterwards whether or not that change succeeded.

### `setPassword`

`{"action": "setPassword", "password": "..."}`

Sets the password of **the calling session's own user**
(`PATCH /users/{id}/password`). Both client call sites are recovery, so
there is no old password to supply and `account.updatePassword` — which
demands one — cannot be used.

Must apply the password policy and answer `400` /
`general_password_weak` (or `password_recently_used`) rather than
accepting a weak one.

---

## 3. `/operation` — the named server-side operations

`AppwriteConfig.operationPath`, `/operation`.

`{"operation": "reopen_report", "params": {"p_report_id": "..."}}`

The RPCs. Today there is exactly one: `reopen_report`, which clears a
report's peer votes, sets it back to pending and reschedules escalation —
senior staff and admin only. It must check the caller's role itself; the
`SECURITY DEFINER` function it replaces did.

---

## Two decisions the client has already made

**The client never asks for a preview.** Uploaded files are read through
`/storage/buckets/{b}/files/{id}/view`, not `/preview`: transformations are
a paid Cloud feature and the app compresses before upload anyway.

**Appwrite cannot join, and the client does not pretend otherwise.**
`DataBackend.listDocuments` takes a best-effort `related`, and the Appwrite
adapter logs and ignores it. The one place the app embeds — a
verification's verifier name — therefore shows no name until Phase 1's
denormalisation lands, which is exactly what it already shows for a profile
the caller may not read. **Denormalising `verifierName` onto the
verification in the `write` Function removes that gap**, and the read path
needs no change when it does.

---

# The worker: four more handlers, nobody calls

The three above answer the client. These four replace the Railway
service, and nothing invokes them — Appwrite does, on events and on a
schedule.

They were four Functions, and they are the second half of the same
two-Function limit: one Function, `worker`, entrypoint
`functions/cradi/src/worker.js`, `execute: []` so no client can reach
it. Which handler runs is the **trigger**:

| trigger | runs |
| --- | --- |
| an event (`x-appwrite-event` is set) | `on-write`, and nothing else |
| the schedule, or a manual HTTP run | the drain, then escalation, then — on every fifth minute — the sweep |

One schedule, `* * * * *`, carries all three cadences: the drain and
escalation ran every minute and the sweep every five, so `worker.js`
checks `getUTCMinutes() % 5` for the third. The three are run
independently and a thrown one is recorded rather than raised — they
were separate Functions, where a crash in the sweep never stopped the
drain — and the response carries each one's summary or its error, with
a 500 when any of them threw.

`x-appwrite-event` rather than `x-appwrite-trigger`, because a manual
run for a test is `http` and must do the scheduled work.

## The collections they need

| Collection | | |
|---|---|---|
| `notification_outbox` | `eventType`, `payload` (JSON text), `attempts`, `availableAt`, `processedAt`, `note` | rebuilt, not dropped — see below |
| `scheduled_escalations` | `reportId`, `escalateAt`, `status`, `reason`, `processedAt` | one per report, id = the report's |
| `sms_deliveries` | `reportId`, `phone`, `lga`, `state`, `status`, `error` | id is the claim |

Indexes that matter: `notification_outbox` on `(processedAt, availableAt,
attempts)`, `scheduled_escalations` on `(status, escalateAt)`, and
`sms_deliveries` on `(lga, state, $createdAt)` for the daily cap.

## `on-write` — the event hook

Subscribed to five document events. It writes **one outbox document and
nothing else**, and that restraint is the whole design: Phase 6 watched
an event Function that throws, given one event, for three minutes. It ran
**once**. No retry, ever; the event is gone. Everything this Function
does is work that can silently not happen, so it does as little as
possible and leaves the rest to a schedule.

It cannot see a *change*, only the document — Appwrite's payload has no
"before". The `write` Function therefore stamps `previousStatus` whenever
it writes `status`, and the **absence** of that field means the edit did
not touch the status. Without that rule every description fix
re-announces the report.

## `drain` — the outbox, every minute

Claims due documents, bumps `attempts`, pushes `availableAt` forward by
`min(60, 2^attempts)` minutes, and gives up at 8 — the same curve
`claim_outbox_events` had.

**There is no atomic claim.** `FOR UPDATE SKIP LOCKED` has no Appwrite
equivalent, so two overlapping runs can claim the same document. What
stands in for it, per Phase 6, is that **Appwrite refuses a duplicate
`messageId` with 409**: the outbox id becomes the message id, and the
second send is refused by the server. Idempotency replaces locking.

That argument does not cover SMS. Termii has no such protection and a
duplicate flood warning to a local authority is not a harmless retry, so
`sms_deliveries` carries the lock instead — a document whose id is
deterministic per `(report, phone)`, written **before** the send. Phase 6
verified the primitive: first insert `201`, second `409`. A crash between
claiming and sending leaves the claim, so that number is skipped rather
than texted twice. A retryable failure deletes the claim so the retry
re-sends only that number; a number the provider rejects keeps its claim
and is recorded.

Without `TERMII_API_KEY` the SMS path is **off**, not broken.

## `escalate` — the deadline, every minute

Reports still `pending` at `escalateAt` are flagged `escalated` (the
status stays `pending`) and coordinators and staff are notified.

Postgres made this safe with conditional updates — the report update
applied only `where escalated = false`. Appwrite has no conditional
update, so it is read-then-write with a window. The push message id is
`escalation:<id>`, so two overlapping runs cost a wasted read rather than
a second notification; marking a report escalated twice is already
idempotent. Failures are counted in `reason` as `attempt N:` — the
collection has no attempts column, and did not in Postgres either — and
give up after 5.

The row itself is created by the `write` Function when the report is
created, not by this one. That is one more non-transactional call, and
the alternative was the event Function, which runs once and is never
retried.

## `reconcile` — the sweep, every five minutes

The honest mitigation for the one loss with no clean fix.

In Postgres the outbox row was written by a trigger **inside the report's
transaction**: both or neither. Here the event Function runs after the
commit and can fail, leaving a report with no outbox document, no
notification, and nothing that will ever notice. That is the single
failure this system exists to prevent.

So this compares recent reports, alerts and disputes against the outbox
documents that should exist, and enqueues what is missing. Three honest
limits:

1. **Creates only.** A missed `report_status_changed` is invisible,
   because nothing records which transitions were announced. Catching
   those needs an announcement log, which is a second outbox.
2. **The window is a guess** — 20 minutes against a 5-minute schedule, so
   four passes before a gap is lost.
3. **It cannot double-notify**, which is the part that *is* exact: outbox
   ids are deterministic, so re-enqueueing something already handled
   collides with a 409.

It logs every run, including quiet ones. "0 missing" is the evidence it
ran at all — a sweep that silently stops looks exactly like a system with
no gaps.
