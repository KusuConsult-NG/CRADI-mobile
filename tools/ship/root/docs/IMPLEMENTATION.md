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

## 3. The Function

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

## 4. Authentication

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

## 5. The mobile app

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

## 6. The admin panel

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

## 7. What CI guarantees

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

What CI does **not** do: deploy the Functions. That is manual, and §8 below
and the cutover runbook say why that is easy to forget.

## 8. Deploying

`./scripts/deploy.sh check` first — it reports which variables and files are
present without printing any value.

| | |
|---|---|
| **Functions** | `./scripts/deploy.sh functions`. Rewrites each Function's variables from the environment it is given, so a missing `TERMII_*` would turn off every authority SMS; the script refuses rather than let that through, and `ALLOW_SMS_OFF=1` is the deliberate override. Confirm each Function reads `ready` with a non-zero build time. |
| **Admin panel** | `./scripts/deploy.sh web` proves the build, then push to the branch Appwrite Sites tracks. Check the adapter is SSR. |
| **Android** | `./scripts/deploy.sh apk`, then compare the APK's SHA-256 against the keystore's. `CN=Android Debug` means the signing config was not picked up. |

Credentials belong in a file outside the checkout:

```bash
set -a; source ~/.cradi/appwrite-cloud.env; set +a
./scripts/deploy.sh functions
```

Full procedure, including the write freeze and the rollback: `mobile/docs/CUTOVER-RUNBOOK.md`.

## 9. What is not in this repository, and why

`env.json`, `web/.env.local`, `android/key.properties`, the signing
keystore. Each carries a credential or is produced per machine. They are
ignored rather than templated-and-ignored, so there is no file that looks
committable and is not.

## 10. Known limitations

- **OTP and reset-email deliverability** — §4. Needs a branded SMTP sender.
- **Phone sign-in is not available.** The path raises `providerDisabled`
  rather than half-working; it was not migrated.
- **Image transformations are off by default.** They are plan-gated on
  Appwrite Cloud and asking for one that is not included returns an error
  instead of the image, so `APPWRITE_IMAGE_TRANSFORMS` stays false unless
  the plan includes them.
- **The Supabase schema is still present** under `mobile/supabase/`. It is
  what the migration pipeline tests against, not a second live backend.
