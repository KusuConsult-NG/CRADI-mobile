# Implementation

How EWER is put together, what each part is responsible for, and what has
to be true for a change to reach production. The deep detail lives in the
documents each section points at; this is the map.

## 1. Shape of the system

Two clients over one backend.

```
  mobile/  Flutter app          ─┐
                                 ├─→  Appwrite Cloud  ──→  Functions (functions/cradi)
  web/     Next.js admin panel  ─┘         │                        │
                                           ├─ Auth                  ├─ /write
                                           ├─ TablesDB              ├─ /auth
                                           └─ Storage               └─ /operation
```

There is no server of our own in the request path. Appwrite holds the
accounts, the data and the files; the only code we run server-side is one
Appwrite Function, and everything else is a client talking to Appwrite
directly under an access-control rule.

The backend was Supabase until the migration in `mobile/docs/APPWRITE-MIGRATION.md`.
That history still matters in two places: `mobile/supabase/` holds the
Postgres schema the data came from, and `mobile/docs/appwrite-spike/migrate/`
holds the pipeline that moved it, which CI still runs against a real
Postgres because a silent regression there once reached production.

## 2. The write policy — the one rule to understand first

A collection is written **either** by the client directly **or** by the
Function, never both. The list is in
`mobile/lib/core/services/appwrite/appwrite_config.dart`:

```dart
static const Set<String> clientWritableCollections = {
  contacts,          // pure owner rule
  messages,          // owner + label:approved
  trusted_devices,   // pure owner rule
  login_history,     // append-only, owner-stamped
  ndpa_consents,     // append-only, owner-stamped
};
```

Those five are the collections whose rule an Appwrite document ACL can
express on its own. Everything else — `reports`, `alerts`, `profiles`,
`verifications`, `authorities`, `scheduled_escalations`, `knowledge_base`,
`app_settings`, `news_links` — goes through the Function, because its rule
depends on something an ACL cannot see: the author's role, how many peers
have confirmed a report, whether an escalation window has elapsed.

So a client write to `reports` is not a database call. It is a Function
execution that validates, then writes with a server key. If the Function
is not deployed, reporting does not work, however healthy the database
looks.

## 3. Who may read what — the counterpart to §2

§2 is about writes. Reads do **not** go through the Function: the app and
the admin panel both call `listRows` under the user's own Appwrite
session. So a report's stored permission list *is* the read rule, and
there is no second place that filters. Get it wrong and the data is
simply visible, with nothing in any log to say so.

`mobile/functions/cradi/src/lib/policy.js` holds the one definition,
`reportAcl`. The client's permission matrix (§4.1 of their spec) asks for
three scopes, and they are expressed as four grants:

| scope | who | how |
|---|---|---|
| own ward | the reporter, and their ward team | `read("user:…")`, `read("team:ward-…")` |
| own LGA | LDP Coordinator | a per-LGA account label |
| all LGAs | Project Staff, EW Verifier, Admin | a flat role label |
| validated only | Early Responder, Media — any location | granted only while the status is `verified` or `approved` |

Three consequences worth knowing before changing any of it.

**An LGA label, not an LGA team.** Ward teams are populated by the
one-time migration seeder and by nothing else in the running system, so
an account created after the cutover belongs to no team at all. A second
kind of team would have inherited that. Labels are re-derived by
`syncLabels` on every profile write that touches a field they depend on —
which is why `state` and `lga` are in `LABEL_FIELDS`: without them a
coordinator moved to another LGA keeps the old LGA's reports.

**An ACL is written once, at creation.** It is not a rule evaluated on
read; it is a list stored on the row. Since every report is created
`pending`, the "validated only" scope would never grant anything, so
`write.js` rewrites the permissions when the status changes (`syncAcl`).
It logs and continues on failure rather than throwing, because by then the
edit the caller asked for has already been applied.

**Changing the rule does not change existing rows.** That is what
`mobile/infra/appwrite/fix-report-permissions.mjs` is for — §9.

Two things the ACL cannot express at all, so they are explicit guards in
`guardReportUpdate`:

- A write arrives through the Function on a server key, so document
  permissions do not apply to it. Without a guard an Early Responder
  holding a report id could move the response status of a report it has
  no way to open; the scope above would be bypassed by the one write it
  is granted.
- `responseStatus` says what the *response* is doing; `status` says
  whether the report is *true*. Different questions, different roles — a
  responder may move the first on a report it cannot approve, and a
  reviewer may approve one it cannot respond to. Neither response stamp
  (`responseUpdatedBy`, `responseUpdatedAt`) can be written on its own,
  or a row could name a responder and a time for a status nobody moved.

Roles are stored in `profiles.role` as `user`, `ewm`, `ewv`, `ewr`,
`ldp_coordinator`, `project_staff`, `admin`, `techSupport`, `media`. Note
`techSupport`, camel-cased, where the others are snake — every writer
stores it that way and the schema CHECK allows only that spelling;
`canonicalRole` accepts the underscored form for rows seeded by hand.
`media` is the only role with no write anywhere.

A role grants nothing until the account is **approved**: `accountLabels`
returns no role label for an unapproved or disabled profile, matching what
the Postgres `app_role()` function did before the cutover.

## 4. The Function

One Function, `functions/cradi`, routed on the execution path rather than
split into several — the Cloud plan allows fewer Functions than this
backend needs.

| Route | Does |
|---|---|
| `/write` | `{op, collection, documentId, data}` → the document. Every Function-written collection. |
| `/auth` | Registration, code resends, password recovery — the steps needing a server key. |
| `/operation` | Named server-side operations (today: reopening a report). |

It has **no dependencies on purpose**. Every dependency is paid again on
each cold start, and that was measured at 735 ms. There is no lock file
and nothing to install.

Contracts: `mobile/docs/APPWRITE-FUNCTION-CONTRACTS.md`.

## 5. Authentication

Email and password, through Appwrite Auth. Three things are worth knowing:

- **Unverified accounts are refused at sign-in.** Appwrite signs them in
  anyway, so the client drops the session again and raises
  `emailNotConfirmed`, which is what routes the user to code entry.
- **One-time codes and password resets go out over Appwrite Cloud's shared
  SMTP** (`POST /account/tokens/email`). It needs no configuration, which
  is why it is in use — but it is a shared sender with no SPF/DKIM/DMARC
  alignment for the project's domain, so deliverability to some providers
  is poor. A branded sender configured in the Appwrite console is the fix;
  until then, OTP non-delivery is expected for some addresses and is not a
  bug in this code.
- **Roles** are `user`, `ewm`, `ewv`, `ewr`, `ldpCoordinator`,
  `projectStaff`, `admin`, `techSupport`. A role only takes effect once the
  account is approved: an unapproved one resolves to `user` everywhere, and
  the router sends it to `/pending-approval`.

## 6. The mobile app

Flutter, pinned to 3.47.5 (`.fvmrc` and the workflow must agree).

**Configuration is compiled in, not read at runtime.** `AppConfig` and
`AppwriteConfig` use `String.fromEnvironment`, so the values arrive at
build time:

```bash
flutter run   --dart-define-from-file=env.json
flutter build apk --release --dart-define-from-file=env.json
```

`env.json` is not in the repository. Copy `mobile/env.example.json`; only
`APPWRITE_ENDPOINT` and `APPWRITE_PROJECT_ID` must be non-empty, the rest
default sensibly.

A build made without it compiles in empty strings, `isConfigured` is false
for the life of that binary, and every backend call fails in a way the app
reports as "signed out" — which is indistinguishable from a broken server.
That mistake cost a day of misdiagnosis, so `main.dart` now refuses to
start and shows a diagnostic screen instead, and CI refuses to build a
tagged release that way.

Release signing needs `mobile/android/key.properties` (also not in the
repository — see `mobile/docs/KEYSTORE_SETUP.md`). Without it the Gradle
build fails deliberately rather than silently debug-signing.

## 7. The admin panel

Next.js 16, deployed to Appwrite Sites.

Two kinds of configuration, and the difference matters:
`NEXT_PUBLIC_APPWRITE_ENDPOINT` and `NEXT_PUBLIC_APPWRITE_PROJECT_ID` are
inlined into the client bundle by `next build`; `APPWRITE_API_KEY` is
server-only and must be marked secret — it must never reach the browser.

**The Sites adapter must be `ssr`.** Framework detection sets the
framework but not the adapter, and under `adapter: static` every route
404s while the build log still reads as a success. This is the single
most common way a deployment of this app appears to work and does not.
`web/SETUP.md` has the settings that are confirmed working.

## 8. What CI guarantees

`.github/workflows/mobile.yml` and `.github/workflows/web.yml`.

| Job | Guards |
|---|---|
| Flutter Analyze & Test | formatting, zero analyzer warnings, the full test suite |
| Build Android Debug APK | the Android build actually compiles |
| Build Android Release APK | tag-only; signs from secrets and **fails if the result is debug-signed** |
| Backend / Migration Tool / Appwrite Functions | three Node suites |
| Appwrite Migration Pipeline | the migration against a real Postgres 16, applying every migration in order |
| Backend Docker Build | the image the backend deploys from |
| Typecheck, Lint & Build | the admin panel, zero warnings |
| Playwright E2E | the admin panel against an in-memory mock, no live project |

What CI does **not** do: deploy the Functions. That is manual, and §9 below
and the cutover runbook say why that is easy to forget.

## 9. Deploying

`./scripts/deploy.sh check` first — it reports which variables and files are
present without printing any value.

| | |
|---|---|
| **Everything** | `./scripts/go-live.sh --apply` — columns, Functions, the permissions migration and the version gate, in order. It refuses to start without the `TERMII_*` pair, because the Functions step would delete whatever is there. |
| **Functions** | `./scripts/deploy.sh functions`. Rewrites each Function's variables from the environment it is given, so a missing `TERMII_*` would turn off every authority SMS; the script refuses rather than let that through, and `ALLOW_SMS_OFF=1` is the deliberate override. Confirm each Function reads `ready` with a non-zero build time. |
| **Admin panel** | `./scripts/deploy.sh web` proves the build, then push to the branch Appwrite Sites tracks. Check the adapter is SSR. |
| **Android** | `./scripts/deploy.sh apk`, then compare the APK's SHA-256 against the keystore's. `CN=Android Debug` means the signing config was not picked up. |

Credentials belong in a file outside the checkout:

```bash
set -a; source ~/.cradi/appwrite-cloud.env; set +a
./scripts/deploy.sh functions
```

### The order matters

```bash
./scripts/go-live.sh            # show the plan, change nothing
./scripts/go-live.sh --apply    # do it
```

That runs the four steps in the only order that works, dry-running the
migration and showing you the counts before it asks. Prefer it to the
individual commands: the ordering below is a constraint, not a
preference, and a script cannot forget it.

```bash
node mobile/infra/appwrite/provision.mjs               # 1. columns
./scripts/deploy.sh functions                          # 2. the rules
node mobile/infra/appwrite/fix-report-permissions.mjs  # 3. existing rows (dry run)
node mobile/infra/appwrite/fix-report-permissions.mjs --apply
```

**1 before 2**, or the Function is deployed with rules whose columns do
not exist and every write to them is refused. **2 before 3**, or the
migration re-derives permissions from the rules the project is still
running — the old ones.

Step 3 exists because of §3: an ACL is a list stored on a row at
creation, not a rule evaluated on read, so changing `reportAcl` governs
the next report and no existing one. Account labels have the same problem
from the other side — `syncLabels` makes an account correct from its
*next* profile edit onward, so a coordinator nobody edits again never
gets their LGA label at all.

`fix-report-permissions.mjs` re-derives both. It is a dry run unless
given `--apply`; it is idempotent, so a run against an already-correct
project writes nothing and a run that dies halfway is finished by running
it again; it pages by cursor rather than offset, because it rewrites rows
as it reads them and an offset into a table being written underneath you
skips rows; and it exits non-zero on a partial run, so a half-done
migration does not read as a finished one. It holds no scope of its own —
the lists come from `reportAcl` and `accountLabels`, the same functions
the Function uses.

`app_min_version` gates the app's "update required" screen. It is a row
in `app_settings` keyed by its own name, editable from the admin panel's
Settings page or directly:

```bash
curl -sS -X PUT \
  "$APPWRITE_ENDPOINT/tablesdb/cradi/tables/app_settings/rows/app_min_version" \
  -H 'content-type: application/json' \
  -H "x-appwrite-project: $APPWRITE_PROJECT_ID" \
  -H "x-appwrite-key: $APPWRITE_API_KEY" \
  -d '{"data":{"key":"app_min_version","value":"1.0.0"}}'
```

Raise it only after the new build is live in the stores: every install
older than this value is locked out until it updates.

Full procedure, including the write freeze and the rollback: `mobile/docs/CUTOVER-RUNBOOK.md`.

## 10. What is not in this repository, and why

`env.json`, `web/.env.local`, `android/key.properties`, the signing
keystore. Each carries a credential or is produced per machine. They are
ignored rather than templated-and-ignored, so there is no file that looks
committable and is not.

## 11. Known limitations

- **OTP and reset-email deliverability** — §5. Needs a branded SMTP sender.
- **Phone sign-in is not available.** The path raises `providerDisabled`
  rather than half-working; it was not migrated.
- **Image transformations are off by default.** They are plan-gated on
  Appwrite Cloud and asking for one that is not included returns an error
  instead of the image, so `APPWRITE_IMAGE_TRANSFORMS` stays false unless
  the plan includes them.
- **The Supabase schema is still present** under `mobile/supabase/`. It is
  what the migration pipeline tests against, not a second live backend.
- **The four response-status names are provisional.** `awaiting`,
  `acknowledged`, `dispatched`, `resolved`. The client's matrix names the
  capability and not the lifecycle, so these are the smallest useful set
  rather than anybody's decision. The stored value and the displayed
  label are separate, so renaming a label is a change to the five `.arb`
  files; renaming a stored value is a data migration. No order is
  enforced between them, deliberately — a response can legitimately go
  backwards, and a strict sequence would be a guess about how the client
  actually works.
- **`ewv` is in the app and absent from the client's matrix.** Left as it
  is: removing a role the spec does not mention would break live
  accounts. It currently reads every LGA.
- **The admin panel's Emergency Contacts tile is wrong for every role**,
  including admin. `contacts` is per-document with client-created rows,
  so each account reads only its own; the tile counts the signed-in
  user's contacts and labels it a system total. Known, separate from the
  role work, and not yet fixed.
