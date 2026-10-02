# The CRADI Appwrite Functions

Three Functions, one source tree. Appwrite lets several Functions share a
root directory and differ only by entrypoint, which is why the helpers in
`src/lib/` exist once rather than three times.

### Called by the client

| Function | entrypoint | called by |
|---|---|---|
| `write` | `src/write.js` | every write to a collection the client may not touch |
| `auth` | `src/auth.js` | registration, code resends, recovery, redeeming a typed code |
| `operation` | `src/operation.js` | the named server-side operations (the old RPCs) |

### The worker, which replaces the Railway service

| Function | entrypoint | trigger |
|---|---|---|
| `on-write` | `src/on-write.js` | document events — writes one outbox document and nothing else |
| `drain` | `src/drain.js` | schedule `* * * * *` — sends what the outbox holds |
| `escalate` | `src/escalate.js` | schedule `* * * * *` — reports still pending at their deadline |
| `reconcile` | `src/reconcile.js` | schedule `*/5 * * * *` — finds events that never happened |

`on-write` subscribes to:

```
tablesdb.cradi.tables.reports.rows.*.create
tablesdb.cradi.tables.reports.rows.*.update
tablesdb.cradi.tables.verifications.rows.*.create
tablesdb.cradi.tables.alerts.rows.*.create
tablesdb.cradi.tables.profiles.rows.*.update
```

**Scheduled Functions need `schedule-functions` and `schedule-executions`
when self-hosting.** Phase 6 lost time to a stack without them: schedules
silently never fire, which looks exactly like "Appwrite cron does not
work". Cloud runs them for you.

The contract each one must meet is
[`docs/APPWRITE-FUNCTION-CONTRACTS.md`](../../docs/APPWRITE-FUNCTION-CONTRACTS.md).
The client side is `lib/core/services/appwrite/`.

## Deploying

Each Function is created separately in the Appwrite console or CLI, all
three pointing at this directory:

| setting | value |
|---|---|
| runtime | Node 22 |
| root directory | `functions/cradi` |
| entrypoint | `src/write.js` / `src/auth.js` / `src/operation.js` |
| build command | *(none — there are no dependencies)* |
| execute access | `users` |

### Scopes

`auth` is the only one that needs more than documents. Give each Function
the narrowest set that works:

| Function | scopes |
|---|---|
| `write` | `databases.read`, `documents.read`, `documents.write`, `teams.read`, `teams.write` |
| `auth` | `users.read`, `users.write`, `sessions.write`, `documents.write`, `messages.write` |
| `operation` | `documents.read`, `documents.write` |
| `on-write` | `documents.write` |
| `drain` | `documents.read`, `documents.write`, `users.write`, `messages.write`, `targets.read` |
| `escalate` | `documents.read`, `documents.write`, `messages.write`, `targets.read` |
| `reconcile` | `documents.read`, `documents.write` |

### Variables

`APPWRITE_FUNCTION_API_ENDPOINT` and `APPWRITE_FUNCTION_PROJECT_ID` are
injected by Appwrite. Set these yourself:

| variable | |
|---|---|
| `APPWRITE_API_KEY` | a server key with the scopes above |
| `APPWRITE_DATABASE_ID` | defaults to `cradi` |
| `TERMII_API_KEY` | `drain` only. Absent, authority SMS is **off** rather than failing |
| `TERMII_SENDER_ID` | `drain` only |

## No dependencies, on purpose

`package.json` has none, and `src/lib/appwrite.js` calls the REST API over
`fetch` rather than using the Node SDK. Phase 4 measured a **735 ms cold
start** on an idle local box with no network in the way; on a quiet night
in a quiet ward, the first report of the morning pays it. Every dependency
is paid again on every cold start, and these Functions need about a dozen
endpoints between them.

## Running the tests

```
cd functions/cradi && npm test
```

107 tests, no server and no network: `test/helpers.mjs` stubs the single
`fetch` every call goes through, which is enough to exercise a whole
handler. They cover the things that decide what the server stores
regardless of what the client sent — Phase 4's "a client cannot approve
its own report", the caller coming from the header and never the body, a
vote taking its ward from the report rather than from the voter, and
recovery answering identically for an address that does not exist.

The worker's tests add the ones that decide whether a warning goes out at
all: that two overlapping drains cannot double-send (the fake refuses a
duplicate `messageId` with 409, exactly as Appwrite does, so the
idempotency tests are not vacuous), that a decision changed since the
event was queued is never announced, that a push outage does not hold
back the authority SMS and the event still retries, and that the
reconciling sweep finds a report whose event Function never ran without
inventing work the trigger would not have created.

What they cannot cover is whether Appwrite behaves as assumed. These run
against a fake; nothing here has met a real server.

## One thing to know before changing `wardTeam`

Document ACLs name a **team**, which is what makes moving an agent between
wards a membership change instead of a rewrite of every document they can
see (Phase 0). So the id has to be a pure function of state, LGA and ward
— and it has to be the *same* function in the write Function and in
`docs/appwrite-spike/migrate/migrate.mjs`, which is why that file imports
this one rather than keeping a copy.

It kept a copy until recently, and the copy was a plain slug. That was
wrong for **35 of the 584 wards**, whose ids run to 50 characters and
exceed Appwrite's 36-character limit —
`ward-plateau-langtang-north-langtang-north-central` is the worst. Those
team creations would have failed in production, for 6% of the country,
only once somebody filed a report there. `test/policy.test.mjs` now checks
all 584 for length and for uniqueness.

Ids that already fit are unchanged, so nothing designed around them moves.
