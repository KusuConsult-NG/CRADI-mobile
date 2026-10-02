# Verifying against Appwrite Cloud

Everything in `docs/APPWRITE-MIGRATION.md` through Phase 21 is verified
against a real Appwrite — **1.9.6, self-hosted in a container**. Cloud
runs 2.x. This file is the sequence that closes that gap, and it has to
be run from a machine that can reach Cloud.

> **This container cannot.** The environment's network policy answers 403
> at the gateway for `fra.cloud.appwrite.io`, for `cloud.appwrite.io` and
> for `appwrite.io` — it has, through every phase. Every contact anything
> in this repository has made with Cloud was the owner running a script
> locally. That is what this file is for.
>
> To run it from a Claude Code session instead, the environment's
> **Network access** setting needs `fra.cloud.appwrite.io` allowed.

## What is already known about the Cloud project

| | |
|---|---|
| Endpoint | `https://fra.cloud.appwrite.io/v1` (Frankfurt) |
| Project | `6941cdb400050e7249d5` |
| Database | `6941e2c2003705bb5a25` — the previous Appwrite build's. The plan allows **one** database and the project already has it, so provisioning goes into that one: `APPWRITE_DATABASE_ID` is a variable, not a change. |
| Buckets | the tier allowed **one**. `provision.mjs --single-bucket` provisions one; the app's bucket ids are `String.fromEnvironment`. Safe only while `fileSecurity` stays on. |

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

# 1. What the plan asks for, against what the tier allows. Read-only.
node infra/appwrite/provision.mjs --dry-run
node infra/appwrite/provision.mjs --probe

# 2. Provision, then confirm. `provision.mjs` stops at the first quota
#    refusal and names it; `verify.mjs` exits non-zero on any difference.
node infra/appwrite/provision.mjs --single-bucket
node infra/appwrite/verify.mjs

# 3. Deploy the seven Functions and wait for their builds.
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

The SMS path now runs end to end against a stand-in
(`infra/appwrite/local/e2e-sms.mjs`): the numbers chosen, the text,
both caps, the deterministic claim and the bookkeeping. What that
cannot prove is Termii's own API contract — that a real key and sender
id are accepted, and that the response shape is what the sender reads —
and that a deployed Function can reach `api.ng.termii.com` at all.

Both need an account and a deploy. Send one message to a number you
own, with `TERMII_BASE_URL` unset, and check `sms_deliveries` says
`sent` with a provider id.

### 2. The tier's real limits

584 teams, ~650 messaging topics, 19 collections, 187 columns, 7
Functions with three on a one-minute schedule. The one-database and
one-bucket limits are known from the project's own history. The rest
have never been measured against the live plan, which is what
`--probe` is for: it keeps going past a quota refusal and lists every
limit in one run, instead of one round trip per limit.

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
