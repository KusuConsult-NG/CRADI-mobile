# Verifying against Appwrite Cloud

Everything in `docs/APPWRITE-MIGRATION.md` through Phase 21 is verified
against a real Appwrite — **1.9.6, self-hosted in a container**. Cloud
runs 2.x. This file is the sequence that closes that gap, and it has to
be run from a machine that can reach Cloud.

> **This container cannot.** The environment's network policy answers 403
> at the gateway for `fra.cloud.appwrite.io`, for `cloud.appwrite.io` and
> for `appwrite.io` — it has, through every phase, and it still did when
> this was re-measured on 7 October 2026. Every contact anything in this
> repository has made with Cloud was the owner running a script locally.
> That is what this file is for.
>
> To run it from a Claude Code session instead, the environment's
> **Network access** setting needs `fra.cloud.appwrite.io` allowed, and
> the six `APPWRITE_*`/`TERMII_*` variables below have to be in the
> environment's settings — a session has none of them today.

## The plan was upgraded — 7 October 2026

The owner upgraded the Cloud plan, so the two-Function cap that stopped
the first run should be gone. **Should**: nothing has been measured
against the new plan from anywhere, which is why `--probe` is still the
first thing in the sequence. What the upgrade does and does not change:

| | |
|---|---|
| **Functions** | The two-Function cap is what the 7→2 consolidation worked around. **The consolidation stays.** It is what the 252 unit tests, the six e2e suites and `APPWRITE-FUNCTION-CONTRACTS.md` describe, and more slots is not a reason to unpick a merge that cost nothing but a widened key scope. Deploy `client` and `worker`. |
| **Buckets** | Going to the two the plan declares — `report-images` and `profile-images`, different ACLs, as `BUCKETS` in `plan.mjs` has always said. So **no `--single-bucket` and no `APPWRITE_BUCKET_ID`** in the sequence below. |
| Database | Still provisioned into the existing one (`APPWRITE_DATABASE_ID`). Whether the new plan allows more is unmeasured and does not matter: one is what this design needs. |
| Everything else | Unmeasured on this plan. `--probe` first, and expect the numbers in `infra/appwrite/README.md` to be stale. |
| Index width, row width | **Unchanged.** Those are MariaDB's 767-byte index limit and the row limit, not the plan's, so the `lengths` the first run needed are still needed. |

Two buckets instead of one also settles a mismatch that would have shown
as broken evidence thumbnails in the admin panel: it builds its image
URLs from `REPORT_IMAGES_BUCKET` in the panel's own `lib/constants.ts`,
which is `report-images`, while the single-bucket project's only bucket
is `6941e4e10034186aded8`. With the planned buckets provisioned, the panel's
default and `AppConfig`'s two defines are correct as they stand — nothing
needs passing at build time. (The constant takes
`NEXT_PUBLIC_APPWRITE_REPORT_IMAGES_BUCKET` now, for a project that goes
back to one.)

**The files already on Cloud do not move.** Whatever was uploaded into
the shared bucket stays there and stays reachable only by that id;
`verify.mjs` lists the bucket as something the plan does not ask for.
That is cheap because `reports` was empty on 3 October — if it is not
empty when you run this, the old rows' images need copying across before
the panel and the app stop finding them.

## First Cloud run — 3 October 2026, from the owner's machine

Cloud answered **2.3.0**. What it settled:

| | Result |
|---|---|
| **Functions** | **The plan allows 2.** The previous build's four were deleted to free their slots; `write` and `auth` were created and `operation` was refused. The design needs 7, three on a one-minute cron. **This plan cannot run the backend** — it needs an upgrade, or the Functions consolidated to two. |
| Buckets | 1. The previous build's `Shared Images Bucket` is reused through `APPWRITE_BUCKET_ID`; `provision.mjs` reconciled it (it had `fileSecurity` off and update/delete for every user). |
| Teams, messaging topics | A probe of each was created and deleted. No refusal. |
| Index width | **767**, summed over each index's string columns. Four indexes were refused until they were given `lengths`; 1.9.6 had not enforced it. |
| Row width | `reports` was full: an earlier build had made `escalationStatus` 8192 wide. It and the unplanned `imageIds` were fixed on the empty table. 38 other columns still differ in size from the plan; `verify.mjs` prints them with `~`. |
| Termii | A real key and the `CRADI` sender id were accepted — `200`, `code: ok`, `message_id` — and the inbox shows the message `Sent`. The send reply's `balance` field read `0` while the account held ₦3,610; do not read it as the balance. Still unverified: that a **deployed Function** can reach Termii, because `drain` cannot be created on this plan. |

`verify.mjs --single-bucket` after the run: every column, index and the
bucket match; the 7 problems left are all Functions.

**Resolved since.** The seven were consolidated into the two the plan
allows: `client` (the three a client calls, routed on the execution's
path) and `worker` (the four the server runs on its own, routed on the
trigger). No handler was rewritten — see
`APPWRITE-FUNCTION-CONTRACTS.md`.

On the Termii line, the half that was about *deployment* is now
covered: `infra/appwrite/local/e2e-sms-deployed.mjs` deploys the
worker with `TERMII_BASE_URL` pointing at a stand-in bound on the
runtimes network's docker gateway — an address only a container can
reach — approves a report, and asserts the stand-in was called. It
was, from a container address, with the deployed key and sender id,
and a second drain did not re-send. So the variable plumbing, the
runtime's egress and its `fetch` all work from inside a deployed
Function.

What is left is the half that needs an account: Termii's own API
contract, from a Function deployed on **Cloud**, to a real number.
That is one run of the same script with `TERMII_BASE_URL` unset and a
real `TERMII_API_KEY` in the environment — and a number whose owner
has agreed to be texted.

## What is already known about the Cloud project

| | |
|---|---|
| Endpoint | `https://fra.cloud.appwrite.io/v1` (Frankfurt) |
| Project | `6941cdb400050e7249d5` |
| Database | `6941e2c2003705bb5a25` — the previous Appwrite build's. The free tier allowed **one** database and the project already had it, so provisioning goes into that one: `APPWRITE_DATABASE_ID` is a variable, not a change. |
| Buckets | the free tier allowed **one** (`6941e4e10034186aded8`, the previous build's, reused). Since the upgrade a plain `provision.mjs` makes the two the plan declares and that one is left alone, holding its files. `--single-bucket` and `APPWRITE_BUCKET_ID` are the one-bucket fallback; neither belongs in a run against this plan. |

The API key must be a **fresh** server key. Two keys from the previous
project are in public git history and must not be reused. The key needs:
`databases.*`, `tables.*`/`documents.*`, `teams.*`, `users.read`,
`users.write`, `functions.*`, `buckets.*`.

## The sequence

```bash
export APPWRITE_ENDPOINT=https://fra.cloud.appwrite.io/v1
export APPWRITE_PROJECT_ID=6941cdb400050e7249d5
export APPWRITE_DATABASE_ID=6941e2c2003705bb5a25
export APPWRITE_API_KEY=...            # a fresh server key
# No APPWRITE_BUCKET_ID: that is the one-bucket fallback, and both scripts
# now ignore it unless --single-bucket is passed (and say they are).

# 1. What the plan asks for, against what the tier allows.
#    --dry-run is read-only. --probe is NOT: it provisions for real and
#    only differs in carrying on past a quota refusal.
node infra/appwrite/provision.mjs --dry-run
node infra/appwrite/provision.mjs --probe

# 2. Provision, then confirm. `provision.mjs` stops at the first quota
#    refusal and names it; `verify.mjs` exits non-zero on any difference.
node infra/appwrite/provision.mjs
node infra/appwrite/verify.mjs

# 3. Deploy the two Functions (`client`, `worker`) and wait for
#    their builds.
node infra/appwrite/local/deploy.mjs      # endpoint comes from the env

# 4. Behaviour. Creates `cloudchk-*` rows and deletes them, including
#    after a failure. Writes nothing it did not create.
node infra/appwrite/cloud-check.mjs

# 5. The SMS path, against a stand-in rather than Termii. Safe on a real
#    project: it texts nobody and removes its own rows.
node infra/appwrite/local/e2e-sms.mjs
```

Then, in the `CRADI-Mobile-Admin` checkout:

```bash
# 6. The admin panel, in a browser, against Cloud.
npm run test:e2e:live:seed
NEXT_PUBLIC_APPWRITE_ENDPOINT=$APPWRITE_ENDPOINT \
NEXT_PUBLIC_APPWRITE_PROJECT_ID=$APPWRITE_PROJECT_ID \
NEXT_PUBLIC_APPWRITE_DATABASE_ID=$APPWRITE_DATABASE_ID \
npm run build && npm start -- -p 3100 &
npm run test:e2e:live
npm run test:e2e:live:clean               # removes the seeded rows
```

## Two console steps no script does

**A Messaging push provider** — the FCM v1 service-account JSON, plus an
APNs key for iOS. Those credentials live inside OneSignal today. Appwrite
Messaging accepts a message with no enabled provider, leaves it
`processing` and reports success, so this is a silent prerequisite rather
than a loud one (`infra/appwrite/local/bootstrap.mjs` records the same
trap for email, which is why the local stack provisions an SMTP provider
by hand). Nothing in `infra/appwrite` creates one, deliberately: it would
put a service-account key in this repository's environment.

Note both provider ids afterwards. A target that names no provider is
filed under the project's *default* push provider, so in a project with
FCM and APNs every device on the non-default platform would be registered
against a provider that cannot reach it — accepted, then silent. The app
build takes them as `--dart-define APPWRITE_PUSH_PROVIDER_ANDROID=...` and
`APPWRITE_PUSH_PROVIDER_IOS=...` (see Phase 25 in `APPWRITE-MIGRATION.md`).

**An email provider**, for the same reason: `/auth` sends its typed codes
through Messaging.

The panel needs a **web platform** registered for its hostname, or
Appwrite refuses every browser request as an unknown origin. `localhost`
for a local run; the Railway domain for the deployed one.

And the Flutter adapters:

```bash
# 7. The client. prep-dart.mjs seeds the accounts and a report filed by
#    somebody else, and prints the defines. Pass them to
#    test/integration and NOT to the whole tree: several unit tests
#    assert what the app does with no backend configured, and these
#    defines configure one.
eval "$(node infra/appwrite/local/prep-dart.mjs)"
flutter test \
  --dart-define=APPWRITE_ENDPOINT="$APPWRITE_ENDPOINT" \
  --dart-define=APPWRITE_PROJECT_ID="$APPWRITE_PROJECT_ID" \
  --dart-define=DART_TEST_SESSION="$DART_TEST_SESSION" \
  --dart-define=DART_TEST_EMAIL="$DART_TEST_EMAIL" \
  --dart-define=DART_TEST_PASSWORD="$DART_TEST_PASSWORD" \
  --dart-define=DART_TEST_USER_ID="$DART_TEST_USER_ID" \
  test/integration
```

`appwrite_sign_in_live_test.dart` is the one to watch: it signs in the
way a returning user does, which went unexercised for most of the
migration.

## What only Cloud can answer

Two things. Everything else on the list above passes against 1.9.6 —
including the two that were on this list in Phase 22 and are not any
more, which are worth recording because the reason they came off it was
not "Cloud said yes".

### Closed in Phase 23, not by Cloud

**`signInWithPassword`** was blamed on the local stack's plain HTTP and
deferred here. It was a bug in the SDK's cookie handling that Cloud
shares: `package:http` joins repeated `Set-Cookie` headers with `", "`,
the SDK splits them on a comma *not* followed by a space, the result is
unparseable, and the failure is swallowed. Every Appwrite cookie carries
`expires=Sat, …`, so the join is always there. Had this run on Cloud
first it would have failed there too. The adapter reads the secret from
the cookie and sets it explicitly now, and
`test/integration/appwrite_sign_in_live_test.dart` covers it.

**`callOperation`** was blamed on `Execution.fromMap` needing 2.3, which
was true. Waiting was still wrong: the app does not only target Cloud,
and a client that cannot call a Function on the server this repository
ships a compose file for is broken rather than blocked.
`appwrite_execution.dart` reads the three fields the adapters want, all
of which have been there since 1.x, and the two skipped tests run.

`cloud-check.mjs` still reports whether the execution carries
`resourceId`/`resourceType`, because knowing which server shape you are
on is worth a line either way.

### 1. Termii

The SMS path runs end to end against a stand-in
(`infra/appwrite/local/e2e-sms.mjs`): the numbers chosen, the payload,
the text, both caps, the deterministic claim, and the bookkeeping after
a success, a refused number and an unpaid account.

The payload is no longer the stand-in's guess at what Termii wants. It
is checked against `backend/src/sms/providers.js` — the Railway worker
that was **in production** — which is a better reference than a
document, because it was delivering messages. Phase 24 found the port
had diverged from it in three ways, one of which (`+234…` where Termii
takes `234…`) would have refused every message.

What is left needs an account:

- that a real key and sender id are accepted, and that Termii's reply
  is the shape the sender reads;
- that a deployed Function can reach `api.ng.termii.com` at all.

Send one message to a number you own, with `TERMII_BASE_URL` unset, and
check `sms_deliveries` says `sent` with a provider id. Put the key in
the environment rather than in a shell — `TERMII_API_KEY` and
`TERMII_SENDER_ID` are read by `drain.js` from the Function's variables,
which `deploy.mjs` sets from its own environment.

### 2. The plan's real limits

584 teams, 19 collections, 189 columns (counted from `plan.mjs`, which
is one more than this said before Phase 25 added `pushTopics` — the old
figure was already short by one), 2 buckets, and 2 Functions, one
of them on a one-minute schedule. Messaging topics are no longer part of
that question: Phase 25 creates one the first time a device in it
registers, so the count is the number of places that have users rather
than 37 states and 770 LGAs provisioned empty. **Every one of
these is now unmeasured**: the numbers in `infra/appwrite/README.md` are
the free tier's, and the plan was upgraded on 7 October. That is what
`--probe` is for: it keeps going past a quota refusal and lists every
limit in one run, instead of one round trip per limit.

The schedule is the one to watch beyond the counts. `worker` runs
`* * * * *` and carries three cadences on it; a plan that floors cron
frequency does not refuse it at provisioning time, it just runs it less
often, and the drain and the escalation sweep both assume a minute. Check
the Function's own schedule in the console after `deploy.mjs` against
what `plan.mjs` asked for — `verify.mjs` compares the two and says so.

## What `cloud-check.mjs` checks, and why each one

Each of these is a question that needed a write to answer, and that a
1.9.6 answer does not settle for 2.x.

1. **The version**, because several answers below depend on it. Read from
   `/health/version`, or from its refusal — a provisioning key has no
   reason to carry the `public` scope, and Appwrite puts the version in
   the error body too.
2. **Labels follow a profile's role.** Phase 21: nothing in the running
   system set an account label, and an unlabelled admin read 0 rows with
   a `200`.
3. **A label-gated read is empty without the label and populated with
   it**, which is the same failure from the other side. Asserted
   explicitly as `200 total=0`, because that is what makes it silent.
4. **The coverage guard** refuses an authority whose LGA names no state,
   and accepts the same LGA in either of its two states. Phase 20: the
   Postgres CHECK that did not survive the migration.
5. **`expect` is a real compare-and-set** — a stale expectation is a 409
   and changes nothing — and the server stamps `previousStatus`, which is
   how the write is shown to have gone through the Function rather than
   straight at the collection.
6. **`app_settings.value` round-trips as a string and refuses a number.**
   Phase 20's second bug.
7. **The execution shape** the Flutter SDK parses (see above).

It deliberately does **not** probe one thing on Cloud: passing bulk
update queries in the *query string* rather than the body. On 1.9.6 the
server ignores them and updates **every row in the table** — measured,
on a throwaway stack, and the reason `updateRowsWhere` and the panel's
`updateRows` both carry a loud comment. That must not be measured on a
real project. Only the correct form is exercised.

## After a Cloud run

- `node infra/appwrite/cloud-check.mjs` cleans up after itself, pass or
  fail, and names anything it could not remove.
- `npm run test:e2e:live:clean` removes the panel suite's seeded rows by
  id — never by prefix. The panel's *own* writes during the run (an
  alert, a knowledge article, a news link, an authority) are not seeded
  rows and are left alone; they carry the run's stamp in their title and
  the script prints it.
- Rotate the key when the verification is done, along with the two
  Termii keys in public git history.
