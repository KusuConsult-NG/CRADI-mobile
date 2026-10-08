# Handoff — where the Appwrite migration stands

Written 3 October 2026, at the end of the session that merged the
migration to `main`. It says what is done, what is left, and the two
things that block the last step. Everything it claims was checked at
the time of writing; where something is unverified it says so.

Both repositories: branch `claude/app-bug-fixes-z3ytqy`, merged to
`main` and pushed.

| Repo | `main` | What landed |
|---|---|---|
| `CRADI-mobile` | `faa20da` | the migration, the 7→2 Function consolidation, eight review fixes, the deployed-SMS proof |
| `CRADI-Mobile-Admin` | `338727f` | the panel on Appwrite, the merged-Function call path, the toast-barrier fix |

---

## Update — 7 October 2026: the Cloud plan was upgraded

The two-Function cap that stopped the 3 October run should be gone. Only
a run can say so — nothing has been measured against the new plan — so
`--probe` stays the first step. What the upgrade changed, and what it did
not:

- **The consolidation stays.** `client` and `worker` are what the tests
  and `APPWRITE-FUNCTION-CONTRACTS.md` describe; extra slots are not a
  reason to unpick them.
- **Buckets go to the two the plan declares** — the owner's call. A plain
  `provision.mjs`, no `--single-bucket`, no `APPWRITE_BUCKET_ID`. The
  shared bucket stays on the project with its files; `verify.mjs` now
  lists it as something the plan does not ask for, and names a stale
  `APPWRITE_BUCKET_ID` instead of quietly switching on it. This also makes
  the admin panel's `report-images` default correct, which against the
  shared bucket it was not — see `CLOUD-VERIFICATION.md`.
- **Nothing else about the plan has been measured.** The limits table in
  `infra/appwrite/README.md` is the free tier's. `--probe` first.
- **Both blockers below still hold**, re-measured on 7 October from a
  session container: 403 at the gateway for `fra.cloud.appwrite.io`,
  `cloud.appwrite.io` and `api.ng.termii.com`, and not one of the six
  variables set. So the order of work has not changed: rotate the keys,
  clear the two settings, then the runbook.

---

## Update — 7 October 2026: a different Cloud project

The work has moved to **`6ac51e70002ab6238fec`**. Everything this file
says about `6941cdb400050e7249d5` — the database to provision into, the
bucket holding the only slot, the pre-consolidation `write` and `auth`
Functions left behind by the 3 October run — describes that project and
not this one. The new project inherits none of it, which removes those
constraints rather than dating them.

What the new project has, as reported by the owner: the two push
providers (`fcm` enabled, `apns` registered but not yet enabled), and a
green run of `infra/appwrite/push-smoke-test.mjs` covering target
registration, topic reconciliation and the Benue→Nasarawa move. What it
still needs is in `CLOUD-VERIFICATION.md`, and the quota numbers in
`infra/appwrite/README.md` are the old project's.

---

## Update — 7 October 2026: push, end to end

The gap that would have shown up as silence after the cutover is closed in
code. `functions/cradi` addressed push topics that nothing was ever
subscribed to, because nothing registered a device as an Appwrite push
target — and Appwrite answers `201` to a message aimed at an empty topic,
so every test and every outbox row said it had been sent.

What landed (Phase 25 in `APPWRITE-MIGRATION.md` has the reasoning):

- the app registers this device as a push target, with the token
  OneSignal already holds, and asks the server to subscribe it;
- the server subscribes each of a user's devices to `all-users`,
  `state-<state>` and `lga-<state>-<lga>` — read back from `alertTopics`
  rather than composed a second time — and unsubscribes the ones a move
  leaves behind, remembering the set in a new `profiles.pushTopics`;
- topics are created when the first device in one registers, which takes
  Phase 3's 650-topic quota question off the table;
- on the Supabase build it all no-ops, so one build can carry both
  through the cutover, which is Phase 3's one mitigation for the fact
  that OneSignal subscriptions cannot be transferred.

**What is still owed is a console job, not code:** Appwrite Messaging
needs a push provider (the FCM v1 service-account JSON, an APNs key for
iOS) and an email provider, and the two provider ids then go into the app
build as `--dart-define`s. Until the provider exists, Messaging accepts a
push and leaves it `processing` — the same silent failure
`bootstrap.mjs` records for email. See `CLOUD-VERIFICATION.md`.

---

## The two blockers, both in environment settings

Neither is a code problem and neither can be worked around from inside
a session.

**1. Egress.** Measured at the time of writing, from this container:

```
fra.cloud.appwrite.io:443 — connect_rejected (organization policy)
api.ng.termii.com:443     — connect_rejected (organization policy)
```

So a Claude Code cloud session cannot reach Appwrite Cloud *or*
Termii. Both hosts need adding under **Network access → Custom →
Allowed domains** (keeping the default package-manager list) in the
environment's settings — the cloud environment menu in the session's
title bar, then Edit. Steps:
<https://code.claude.com/docs/en/cloud-environments#network-access>

Until then the Cloud sequence has to be run from a machine that can
reach both, which is how every Cloud contact in this repository has
happened so far.

**2. Credentials.** Nothing in a session's environment today. These
belong in the environment's settings, never pasted into a chat; a
**new** session picks them up.

```
APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID, APPWRITE_API_KEY   # Cloud
APPWRITE_DATABASE_ID                                       # see CLOUD-VERIFICATION.md
TERMII_API_KEY, TERMII_SENDER_ID
```

`APPWRITE_BUCKET_ID` is no longer one of them: it belongs to the
one-bucket fallback, and setting it on this plan only earns a line of
output saying it was ignored.

---

## Do this first: rotate five keys

Three Appwrite keys were pasted into a chat and two Termii keys are in
**public git history**. All five must be rotated, and the Appwrite one
before a fresh key goes into environment settings, so it is one
rotation rather than two. The owner deferred this deliberately
("we will use the current keys until we are done fixing the app") —
the app is now done.

Rotating does not rewrite the history those keys are in. Treat them as
burned, not hidden.

---

## The one unfinished verification

**A real Termii SMS, from a Function deployed on Cloud.** Everything
either side of it is proven:

- the send path itself — numbers, text, both caps, the deterministic
  claim, the bookkeeping — by `infra/appwrite/local/e2e-sms.mjs`,
  against a stand-in Termii;
- that a **deployed Function container** can reach Termii and send, by
  `infra/appwrite/local/e2e-sms-deployed.mjs`. The stand-in binds on
  the docker gateway of the runtimes network, so only a request from
  inside a container can arrive; the last run was reached from
  `172.21.0.69`. Point it at `127.0.0.1` instead and the run fails,
  which is how you know the hop is real.

What is left is Termii's own API contract, from Cloud. Once both
blockers above are cleared, run the sequence in
`docs/CLOUD-VERIFICATION.md`, then:

```bash
SMS_LIVE_NUMBER=+234XXXXXXXXXX node infra/appwrite/local/e2e-sms-deployed.mjs
```

### Read this before running it live

`notifyApproved` texts **every authority covering the report's LGA**.
The blast radius is not the number you pass — it is whoever already
covers that LGA in the project, and on Cloud those are real
local-government contacts.

The script guards this: after inserting its own authority it lists
everything covering that LGA and stops unless its own row is the only
one, naming the numbers it would otherwise have reached. It also
refuses to start without `TERMII_API_KEY` and `TERMII_SENDER_ID`, or
with a number that is not full E.164 (`08031234567` is refused rather
than normalised). `SMS_TEST_LGA` / `SMS_TEST_STATE` pick a different
LGA. Do not remove these to make a run go through.

Evidence to keep: the delivery row must read `sent`, and the script
prints Termii's `message_id` from the execution log — that is what
matches against their dashboard and the handset.

---

## Cloud is not yet carrying the consolidated Functions

The 3 October Cloud run created `write` and `auth` and was refused the
third, because **the free plan allowed two Functions** and the design had
seven. That is what the consolidation fixed: `client` routes the three
a client calls on the execution path, `worker` routes the four the
server runs on its own by trigger. See
`docs/APPWRITE-FUNCTION-CONTRACTS.md`. The cap has since been lifted and
the consolidation is staying — it is what everything is tested against.

Cloud still holds whatever that run left. Expect `provision.mjs` to
want to remove the old Function rows. Run `cloud-check.mjs` after the
deploy and before the live SMS.

---

## Where the verification lives

Against a real Appwrite 1.9.6 in a container, all passing at the time
of writing:

```bash
./infra/appwrite/local/up.sh
node infra/appwrite/local/bootstrap.mjs
source infra/appwrite/local/.env.local
node infra/appwrite/provision.mjs && node infra/appwrite/verify.mjs
node infra/appwrite/local/deploy.mjs
```

| | |
|---|---|
| `functions/cradi` → `npm test` | 252 unit tests |
| `flutter test` | 830 tests |
| `flutter test test/integration` | 29, against the live server — needs every define `prep-dart.mjs` exports, **including `DART_TEST_FOREIGN_REPORT`** |
| `infra/appwrite/local/e2e*.mjs` | six suites |
| `infra/appwrite/cloud-check.mjs` | the behaviour a Cloud run must also show |
| admin `npm run test:e2e` | 98 specs, against the mock |
| admin `npm run test:e2e:live` | 12 specs, against a real Appwrite |

The admin live suite needs the app built against the same endpoint and
served on `:3100` first — `e2e/live.config.ts` has the sequence.

---

## Two habits this migration was repeatedly caught by

Worth keeping, because each cost real debugging time.

**A fake built from the code it tests can only confirm the code agrees
with itself.** This burned three separate tests: a mock whose lists
were unfiltered, an SMS stand-in that agreed with the production bug
about a leading `+`, and a suite that `await`ed a builder the one real
caller does not. Each time the fix was to derive the expectation from
an independent source — the production Railway worker, the real
producer function, the committed schema. `query-attributes.test.mjs`
is the pattern: it reads `infra/appwrite/columns.json`, so a column
renamed in the plan and forgotten in a Function fails there.

**Appwrite answers an unpermitted read with `200 {"total": 0}`, not an
error.** Several bugs hid behind that. A test asserting "none found"
proves nothing unless something in the same run proves the row is
visible when it should be.
