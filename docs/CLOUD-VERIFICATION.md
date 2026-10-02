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
```

Then, in the `CRADI-Mobile-Admin` checkout:

```bash
# 5. The admin panel, in a browser, against Cloud.
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
# 6. The client. Needs a session for a seeded account; prep-dart.mjs
#    mints one against whatever endpoint is configured.
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

## The three things only Cloud can answer

Everything else in the list above has passed against 1.9.6. These have
not, and cannot.

### 1. `signInWithPassword` on the Flutter client

The headline gap, open since Phase 16.
`AppwriteAuthBackend.signInWithPassword` relies on the Flutter SDK's
cookie jar. Against the local stack the session is created — 201 with
three `Set-Cookie` headers — and **the next call is a guest**. Not a
timing race; a 250 ms wait does not help. The fallback header Appwrite
exposes for exactly this case is browser-only in the SDK.

Plain HTTP, the `.local` suffix and the local cookie attributes are all
candidates, and every Appwrite Flutter app in the world signs in this way
over HTTPS, so it very likely works on Cloud. **"Very likely" is not a
test.** Until step 6 passes, sign-up and recovery are the only verified
paths to a session (they go through `_establish` with a server-minted
secret, which does work).

The admin panel's result does **not** transfer. Phase 21 proved the
panel's session survives — but by measuring that the browser holds *no
cookie at all* and the Web SDK falls back to `localStorage`. That
fallback is the thing the Flutter SDK does not have.

### 2. `DataBackend.callOperation`

The Flutter SDK (27.x) parses an execution with `resourceId` and
`resourceType`, which arrived in Appwrite **2.3**. Neither 1.8 nor 1.9
sends them, so `Execution.fromMap` throws `Bad state: No element` before
the response body is read — in the SDK's model, not in our code. Two
integration tests are skipped with that reason; `cloud-check.mjs` step 7
reports which keys the execution actually carried, and says so when they
are missing. On Cloud those two tests should be un-skipped.

The Function itself is covered over HTTP by
`infra/appwrite/local/e2e-operation.mjs` and by `cloud-check.mjs`, so
what is unverified is the adapter, not the operation.

### 3. The tier's real limits

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
