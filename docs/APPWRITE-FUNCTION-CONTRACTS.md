# The three Functions the client adapters call

The Appwrite adapters in `lib/core/services/appwrite/` are written against
these three Functions. Nothing here is deployed — this is the specification
the server side has to meet, derived from what Phases 1–4 proved and from
what the client now actually sends.

Every Function:

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

## 1. `write` — the collections the client may not write

`AppwriteConfig.writeFunctionId`, default `write`.

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

## 2. `auth` — everything that needs a server API key

`AppwriteConfig.authFunctionId`, default `auth`.

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

## 3. `operation` — the named server-side operations

`AppwriteConfig.operationFunctionId`, default `operation`.

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
