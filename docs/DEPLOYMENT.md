# EWER / CRADI — deployment runbook (Appwrite stack)

End-to-end, first-time deployment, in dependency order. Written to be
followed with the console open: every step says what to do, what it needs
from the step before, and how to tell it worked before you move on.

This is the stack the app and the admin panel are written against. The
Supabase stack that is still in production has its own runbook —
`DEPLOYMENT-SUPABASE.md` — and stays up until the cutover is done; see
*The cutover* at the end.

**Repositories**

| Repo | Contains |
| --- | --- |
| `KusuConsult-NG/CRADI-mobile` | Flutter app (`lib/`), the two Appwrite Functions (`functions/cradi/`), the provisioning scripts (`infra/appwrite/`), the Supabase-era worker and schema (`backend/`, `supabase/`) kept for the old stack |
| `KusuConsult-NG/CRADI-Mobile-Admin` | Next.js admin panel |

**Order matters.** The project and its API key come before anything can
be provisioned; the schema comes before the Functions have anything to
write; the Messaging providers come before a notification can be
delivered; the admin panel's domain has to be a registered platform
before a browser can talk to Appwrite at all; and the app build needs the
project's ids.

```
1. Console: project, key, platforms, providers
        ↓
2. Provision the schema  →  3. Deploy the two Functions  →  4. First admin
        ↓                                                          ↓
5. Admin panel (Railway)  ←───────────────────────────────────────┘
        ↓
6. Mobile app build  →  7. Smoke test
```

### Secret handling — read once

| Secret | Belongs in | Must never be in |
| --- | --- | --- |
| Appwrite **server API key** | your shell for provisioning, the Railway admin panel's `APPWRITE_API_KEY`, the Functions' own variables (set by `deploy.mjs`) | the Flutter app, any `NEXT_PUBLIC_*` variable, any committed file |
| **Termii** API key and sender id | the `worker` Function's variables, set from the environment by `deploy.mjs` | the app, the panel, anywhere committed |
| FCM service-account JSON, APNs key | the Appwrite console's Messaging providers | anywhere else, including this repository |
| Appwrite **endpoint** and **project id** | anywhere (they are public; access is enforced by permissions, labels and the Functions) | — |

The API key **bypasses every permission**, including the document-level
ACLs that are the whole access-control design. Treat it exactly as the
Supabase service role key was treated: a server-side secret, and nothing
else.

Two Appwrite keys and two Termii keys are in these repositories' **public
git history** and must be rotated at the vendor; see *Do this first* in
`HANDOFF.md`. Rewriting history does not help — assume they are known.

---

## 1. In the console, by hand

Four things no script creates, for good reasons: the project is a billing
decision, the region cannot be changed afterwards, a platform is a
browser-origin trust decision, and a provider means uploading a Google
service-account key.

### 1a. The project and its region

Create the project. **The region cannot be changed later** — moving an
Appwrite Cloud project between regions means migrating everything a
second time. The existing project is Frankfurt (`fra`), which is what
`infra/appwrite/plan.mjs` defaults to.

Note the **project id** and the **API endpoint**. The endpoint must end in
`/v1`: it is the REST base, and without it every call lands on the
console's HTML and 404s.

### 1b. A server API key

**Overview → Integrations → API keys.** It needs:

```
databases.read  databases.write
tables.read     tables.write      (documents.read / documents.write on older servers)
teams.read      teams.write
users.read      users.write
functions.read  functions.write
buckets.read    buckets.write
```

Make it a **fresh** key. Do not reuse either of the two in public git
history.

### 1c. A web platform for every browser origin

**Settings → Platforms → Web.** Appwrite refuses a browser request from an
origin it does not know, and the failure reads as a CORS error rather than
as a misconfiguration.

- `localhost` for local work on the panel;
- the Railway domain once step 5 has generated one.

The mobile app does not need a platform entry (it is not a browser
origin), but Flutter **web** builds would.

### 1d. Messaging providers — and the way this fails

**Messaging → Providers.** Two are needed:

| Provider | For | Credentials |
| --- | --- | --- |
| **Push** — FCM | Android devices | the FCM v1 **service-account JSON** |
| **Push** — APNs | iOS devices | an APNs **`.p8` key**, key id, team id, bundle id |

**No email provider is needed.** `/auth` sends its typed codes with
`POST /account/tokens/email`, which mails them over Appwrite Cloud's
shared SMTP. An email provider here buys only branding and a custom
template; the codes arrive without one. It was a Messaging send until the
provider's absence broke every password reset in production — see
`functions/cradi/src/auth.js`. A self-hosted instance is the opposite
case: it has no shared SMTP, so it needs `_APP_SMTP_*` set and a
`worker-mails` container, as `infra/appwrite/local/docker-compose.yml`
now does.

> **Appwrite accepts a message with no enabled provider.** It answers
> success, leaves the message `processing`, and delivers nothing. So a
> missing provider is not a loud failure at deploy time — it is silence
> afterwards. That still applies to everything else Messaging carries:
> push, and any email the outbox sends.

**State on project `6ac51e70002ab6238fec`:**

| Provider | Id | Status |
| --- | --- | --- |
| FCM | `fcm` | **enabled**, with the service-account credentials from Firebase project `ewer-8f788` — the same project `android/app/google-services.json` names |
| APNs | `apns` | **registered, not enabled.** It needs the Apple `.p8` AuthKey, its Key ID and the Team ID. Registered for bundle id `com.westgatestratagem.climateapp.climateApp`, which matches `PRODUCT_BUNDLE_IDENTIFIER` in the Xcode project |

So Android push has a provider and iOS does not — and iOS additionally
has no `GoogleService-Info.plist` (§ 1f), so there is no token to deliver
to either. Both are required before iOS push works at all.

**Both ids have to reach the app build**, as
`--dart-define APPWRITE_PUSH_PROVIDER_ANDROID=fcm` and
`--dart-define APPWRITE_PUSH_PROVIDER_IOS=apns` (§ 6). A target that names
no provider is filed under the project's *default* push provider: with
only FCM enabled that happens to be right, which is exactly why it is
worth binding explicitly now — the day APNs is enabled, an unbound iOS
target goes to FCM, is accepted, and is silent.

> `infra/appwrite/push-smoke-test.mjs` binds the provider the way the app
> does, from `APPWRITE_PUSH_PROVIDER_ANDROID` (default `fcm`), and reads
> the binding back off the created target — so a green run now covers it.
> Set that variable to empty to exercise the unbound case deliberately.

### 1e. Auth settings

**Auth → Settings**: Email/Password enabled. The app's own flows mint
their codes through the `auth` route of the `client` Function, but the
panel signs in with email and password.

### 1f. Firebase, for the device token

Appwrite Messaging delivers *through* FCM and APNs, but the token it
delivers to is minted by Firebase on the device. So the app needs Firebase
platform configuration, and it is not a `--dart-define`:

| Platform | File | State |
| --- | --- | --- |
| Android | `android/app/google-services.json` | **committed**, for Firebase project `ewer-8f788` |
| iOS | `ios/Runner/GoogleService-Info.plist` | **missing** |

For iOS: Firebase console → the project → add an iOS app with bundle id
`com.westgatestratagem.climate_app.climate_app`, download the plist, and
**add it to the Runner target in Xcode** (*File → Add Files*, tick Runner)
— dropping it in the folder is not enough, it has to be in *Copy Bundle
Resources*. Then upload the APNs `.p8` key to Firebase as well, since FCM
is what talks to APNs.

Without it, `Firebase.initializeApp()` throws, `main.dart` catches it and
logs *"FCM unavailable on this build (push disabled)"*, and the app runs
with no push at all on iOS. It does not crash, and nothing in the UI says
so beyond `isPushAvailable` being false.

`google-services.json` is client configuration and is designed to ship
inside the APK — it is not a secret in the way the Appwrite API key is.
But this repository is public, so confirm in the Google Cloud console that
its `AIzaSy…` key carries **application restrictions** (package name plus
the release SHA-1) and **API restrictions**; an unrestricted key of that
shape can be used against other Google APIs billed to the project.

---

## 2. Provision the schema

Everything in this step is `infra/appwrite/` and is idempotent: every
object is checked before it is written, and a half-finished run is
resumed by running it again. **It never deletes anything** — a column in
the project and not in the plan is reported, not dropped.

```bash
export APPWRITE_ENDPOINT=https://fra.cloud.appwrite.io/v1
export APPWRITE_PROJECT_ID=<project id>
export APPWRITE_API_KEY=<the fresh server key>
export APPWRITE_DATABASE_ID=<database id>   # an existing database, or let the plan create `cradi`

node infra/appwrite/provision.mjs --dry-run   # read-only: what it would do
node infra/appwrite/provision.mjs --probe     # NOT read-only: provisions, and
                                              # carries on past a quota refusal
                                              # to list every limit in one run
node infra/appwrite/provision.mjs             # the real run
node infra/appwrite/verify.mjs                # non-zero on any difference
```

What this creates: the database, 19 collections with their columns and
indexes, and the two buckets (`report-images`, `profile-images`). What it
does **not** create: the project, the API key, the platforms, the
Messaging providers, the ward teams (those are made on demand by the
Functions and by the migration pipeline) and the messaging topics (created
when the first device belonging in one registers — Phase 25).

Read before you run it:

- **`--probe` writes.** It differs from a real run only in carrying on
  past a quota refusal. On a plan whose limits you do not know, that is
  the cheap way to learn them all; on a project holding real data, read
  `--dry-run` first.
- **The plan's limits are not measured.** The numbers in
  `infra/appwrite/README.md` are the free tier's, from 2 October 2026.
  The plan has been upgraded since and nothing has been re-measured.
- **One bucket instead of two** is still supported for a tier that allows
  one: `provision.mjs --single-bucket` with `APPWRITE_BUCKET_ID` naming
  the slot that is taken. On this plan it is the fallback, not the path —
  see `CLOUD-VERIFICATION.md`.
- **Index and row widths are MariaDB's**, not the plan's. Four indexes
  need explicit `lengths` to stay inside the 767-byte limit, and a string
  column sized generously costs four bytes per character of the 65,535 a
  row gets. `extract-schema.mjs` sizes them for that; do not widen a
  column without reading its comment.

`verify.mjs` prints three kinds of line: a problem (and exits non-zero), a
`~` for a column whose size differs from the plan (informational — the
project is the one that was built first), and a `?` for something the plan
does not ask for, which is how a leftover bucket or column gets named
instead of going quiet.

---

## 3. Deploy the two Functions

```bash
# Still in the shell from step 2, plus the SMS credentials:
export TERMII_API_KEY=<key>
export TERMII_SENDER_ID=CRADI

node infra/appwrite/local/deploy.mjs
```

It lives under `local/` because that is what it was written for, and it
deploys to Cloud the same way — the one thing that differs between the two
is how a running Function reaches the API back, and that is derived from
the endpoint rather than hardcoded.

| Function | Entrypoint | Trigger | What it is |
| --- | --- | --- | --- |
| `client` | `src/client.js` | the app and the panel, synchronously | the three routes a client calls: `/write`, `/auth`, `/operation`. `execute: ['any']`, because `/auth` must be reachable before there is a session; `/write` and `/operation` check the caller themselves |
| `worker` | `src/worker.js` | events, and `* * * * *` | the outbox drain, the escalation cron, the reconciling sweep, and the write events. `execute: []` — no client can reach it |

Two, not seven, because the free plan allowed two: `docs/APPWRITE-FUNCTION-CONTRACTS.md`
has the routing and the reasoning, and the merge stays on the upgraded
plan because it is what everything is tested against.

**There is no Railway backend service on this stack.** `worker` is what
`backend/` was: the outbox, the escalation cron and the Termii send, on
Appwrite's own scheduler. `backend/` stays in the repository because it is
what the Supabase stack still runs in production, and it reads and writes
Supabase — pointing it at this project is not possible and not needed. The
only Railway service here is the admin panel (step 5).

> **`deploy.mjs` replaces a Function's variables wholesale.** It deletes
> what is there and sets what its environment carries. A `TERMII_API_KEY`
> typed into the console by hand is gone after the next deploy, and the
> script says so in its output: `SMS: OFF` means the two Termii variables
> were not in the shell, and every authority SMS will be skipped.

**Verify:**

- `node infra/appwrite/verify.mjs` → both Functions present, deployed,
  build `ready`, scopes complete, and `worker`'s schedule exactly
  `* * * * *`. A Function with no deployment answers every call with a
  500 and looks fine in the console.
- `node infra/appwrite/cloud-check.mjs` → the behaviour a live project
  must show: labels follow a profile's role, a label-gated read is empty
  without the label and populated with it, the coverage guard, `expect`
  as a real compare-and-set, `app_settings.value` round-tripping as a
  string. It creates `cloudchk-*` rows and removes them, pass or fail.
- A plan that floors cron frequency does not refuse a one-minute
  schedule, it just runs it less often — and the drain and the escalation
  sweep both assume a minute. Check the schedule the console reports
  against what was asked for.

---

## 4. The first admin

The account must exist first: sign up in the app, or create it in the
console under **Auth → Users** and confirm the address.

```bash
cd ../CRADI-Mobile-Admin
APPWRITE_ENDPOINT=$APPWRITE_ENDPOINT \
APPWRITE_PROJECT_ID=$APPWRITE_PROJECT_ID \
APPWRITE_API_KEY=$APPWRITE_API_KEY \
APPWRITE_DATABASE_ID=$APPWRITE_DATABASE_ID \
npm run set:admin -- admin@example.org
```

It sets the `profiles` row (`role = 'admin'`, `isApproved`, not disabled)
**and the account's labels**, which is what the `read("label:admin")`
permissions actually check. Without the label the panel signs in and shows
nothing at all, because Appwrite answers a read you have no permission for
with `200 {"total": 0}` rather than an error. That empty-but-successful
answer is the single most misleading failure on this stack: if a list is
empty and nothing looks wrong, suspect a label before you suspect the
data.

Every other account needs an admin to approve it (Admin → Users →
Approve).

---

## 5. Admin panel (Railway)

Full steps, variables and troubleshooting: **`CRADI-Mobile-Admin/SETUP.md`**.
What matters for the order here:

| Variable | When it is read | |
| --- | --- | --- |
| `NEXT_PUBLIC_APPWRITE_ENDPOINT` | **build time** (inlined) | must end in `/v1`; also becomes the CSP's `connect-src`/`img-src` origin |
| `NEXT_PUBLIC_APPWRITE_PROJECT_ID` | **build time** | public |
| `NEXT_PUBLIC_APPWRITE_DATABASE_ID` | **build time** | optional; defaults to `cradi` |
| `APPWRITE_API_KEY` | runtime, server only | the `/api/admin/*` routes. Never prefix it with `NEXT_PUBLIC_` |

> `NEXT_PUBLIC_*` values are **inlined into the bundle by `npm run build`**,
> so setting or changing one later does nothing until you trigger a fresh
> deploy — a restart re-uses the same bundle. And `GET /api/health` returns
> `{"ok": true}` unconditionally, so **Railway's healthcheck passes on a
> completely misconfigured app.** Verify by opening the site and signing
> in, never by the healthcheck.

Then: generate the domain, and **add it as a web platform** (step 1c) or
every request from it is refused.

The panel also reads `NEXT_PUBLIC_APPWRITE_FN_CLIENT` (default `client`)
and `NEXT_PUBLIC_APPWRITE_REPORT_IMAGES_BUCKET` (default `report-images`);
neither needs setting against a project provisioned by step 2.

---

## 6. Mobile app build

All runtime configuration is compile-time (`String.fromEnvironment`), in
`lib/core/constants/app_config.dart` and
`lib/core/services/appwrite/appwrite_config.dart`.

**Appwrite is the only backend.** Without `APPWRITE_ENDPOINT` and
`APPWRITE_PROJECT_ID` the app starts and behaves as permanently signed
out — `backend.dart` hands out `UnconfiguredDataBackend` and
`UnconfiguredAuthBackend` — which is what unit tests and UI work use, and
what must never reach Play. The release job fails rather than build it.

| `--dart-define` key | Required? | Value | Effect when empty |
| --- | --- | --- | --- |
| `APPWRITE_ENDPOINT` | **yes** | `https://fra.cloud.appwrite.io/v1` | the build falls back to the Supabase backend |
| `APPWRITE_PROJECT_ID` | **yes** | the project id | as above |
| `APPWRITE_DATABASE_ID` | if not `cradi` | the database id | defaults to `cradi` |
| `APPWRITE_FN_CLIENT` | no | the client Function's id | defaults to `client` |
| `APPWRITE_PUSH_PROVIDER_ANDROID` | for push on Android | the FCM provider's id | the target names no provider and is filed under the project's default — wrong, and silent, in a two-provider project |
| `APPWRITE_PUSH_PROVIDER_IOS` | for push on iOS | the APNs provider's id | as above |
| `SENTRY_DSN` | no | Sentry DSN | crash reporting disabled |
| `APPWRITE_IMAGE_TRANSFORMS` | no | `true` | smaller renders are not requested; the full-size image is used |
| `PROFILE_IMAGES_BUCKET` / `REPORT_IMAGES_BUCKET` | only on a one-bucket tier | the shared bucket's id | the planned ids, which step 2 provisions |

**There is no push define.** The device token comes from
`firebase_messaging`, which reads Firebase's own platform files — see § 1f.
A build whose Firebase config is missing or wrong has no token, registers
no Appwrite target, and receives nothing; `NotificationService.isPushAvailable`
is what reports that state.

### Push, and the two topic namespaces that look alike

Delivery is: the `worker` Function posts to **Appwrite Messaging**, which
sends through its FCM or APNs provider to the **Appwrite push targets**
subscribed to the Appwrite **topic** it addressed. The app's part is to
register its FCM token as a target and call `sync_push_subscriptions`;
the server does the rest (`functions/cradi/src/lib/topics.js`).

> `notification_service.dart` *also* calls
> `FirebaseMessaging.subscribeToTopic` with names like `all-users` and
> `lga_obi`. **Nothing sends to those.** FCM topics and Appwrite Messaging
> topics are separate namespaces that here happen to share the string
> `all-users`, and the server has no direct-FCM path. Those calls are
> inert; do not read a device's FCM topic list as evidence of anything.

### `APPWRITE_IMAGE_TRANSFORMS` (optional smaller renders)

Delivery only. When set, `AppwriteDataBackend.displayUrl` asks Appwrite
for the image at the size the view will draw it, by swapping `/view` for
`/preview`:

```
<endpoint>/storage/buckets/report-images/files/<id>/view?project=<p>
  ->  <endpoint>/storage/buckets/report-images/files/<id>/preview?project=<p>&width=320&quality=70
```

**Off by default**, because image transformations are gated by plan on
Appwrite Cloud: where they are not included the request answers with an
error instead of the image, so switching this on without the plan turns
every thumbnail into a broken image. Self-hosted has no such limit.
Confirm against the project before enabling it.

This is a second-order saving in any case. The first-order one is the
small copy uploaded beside each photo, which is used either way —
`DataBackend.thumbUrlFor` names it, and the full-size image is the
fallback when it is missing.

### Using `env.json`

```bash
cp env.example.json env.json     # env.json is git-ignored
# fill in APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID, APPWRITE_DATABASE_ID,
# the two push provider ids, SENTRY_DSN
flutter pub get
flutter run   --dart-define-from-file=env.json
flutter build apk --release --no-tree-shake-icons --dart-define-from-file=env.json
```

`env.example.json` is the template. It ships with **`APPWRITE_PROJECT_ID`
empty**, deliberately: an unedited copy configures nothing and the app starts
permanently signed out, which is a clearer failure than pointing at a project
that does not exist.

The CI release job writes `env.json` from repository secrets of the same
names — `APPWRITE_ENDPOINT`, `APPWRITE_PROJECT_ID`,
`APPWRITE_DATABASE_ID`, `APPWRITE_PUSH_PROVIDER_ANDROID`,
`APPWRITE_PUSH_PROVIDER_IOS`, `SENTRY_DSN` — dropping the empty ones, and
**fails the build if the endpoint and project id are not both set**, since
that APK would install and behave as signed out. Push needs no secret
here; it needs the Firebase files in § 1f. Signing:
`docs/KEYSTORE_SETUP.md`.

> **No server secret is ever passed to the app** — not in `env.json`, not
> as a define, not obfuscated. The app never sends a push or an SMS
> itself; it asks a Function to. Anything compiled into an APK can be
> extracted from it.

### iOS — platform configuration

Full detail lives in `ios/README.md`; the points that affect a release:

**Minimum iOS version is 15.0.** `onesignal_flutter` 5.7.0 requires it. It is
set in `ios/Podfile` (`platform :ios, '15.0'` plus a `post_install` hook that
pins every pod to the same value) and in all three build configurations of
`ios/Runner.xcodeproj/project.pbxproj`. Change both or `pod install` fails.

**Push entitlements are split per configuration** — no manual edit before an
archive:

| Configuration | `CODE_SIGN_ENTITLEMENTS` | `aps-environment` |
| --- | --- | --- |
| Debug / Profile | `Runner/Runner.entitlements` | `development` |
| Release | `Runner/RunnerRelease.entitlements` | `production` |

TestFlight and App Store builds are Release builds, so they carry
`production`. With `development` in an uploaded build, APNs tokens are issued
against the sandbox and **every push silently fails** — and on this stack that
now means the Appwrite target carries a sandbox token too, so the failure
survives the cutover.

**Permission prompts are localized** through
`ios/Runner/<lang>.lproj/InfoPlist.strings` (en, ha, yo, ig, pcm), listed in
`CFBundleLocalizations`. They are already referenced from the Xcode project as
an `InfoPlist.strings` variant group in *Copy Bundle Resources*; if a new
language is added, drop the `.lproj` folder in and add it to that group in
Xcode (*File → Add Files*, then tick the Runner target), and to
`CFBundleLocalizations`.

**Info.plist hygiene for App Review.** `UIBackgroundModes` lists only
`remote-notification` (no background fetch is implemented) and
`NSLocationAlwaysUsageDescription` has been removed — the app only ever
requests when-in-use location. Do not re-add either without an implementation
to point at.

#### Export compliance — a decision is still open

`ITSAppUsesNonExemptEncryption` is **not** in `Info.plist`, so App Store
Connect asks the encryption question on every upload. It was left out
deliberately rather than answered `false`. What the app actually does, read
off the code rather than from memory:

* `lib/core/services/hive_encryption_service.dart` opens the local Hive boxes
  with **`HiveAesCipher`** (AES-256). The key is `Hive.generateSecureKey()`,
  held in `flutter_secure_storage` — the iOS Keychain, with
  `first_unlock` accessibility.
* `lib/core/services/secure_storage_service.dart` is the same store for
  smaller secrets.
* `package:crypto` is a dependency, used for hashing (digests, the device
  fingerprint), not for encryption.
* Everything else is HTTPS/TLS and the platform's own crypto.

> **A correction to an earlier version of this section.** It also cited
> `lib/core/services/encryption_service.dart` implementing AES-256-GCM with
> PBKDF2-SHA256 through PointyCastle. **That file does not exist and never
> has in this repository**; PointyCastle is not a dependency and nothing in
> `lib/` implements either primitive. Anyone who answered the export
> question on the strength of that line should re-read this list.

Whoever owns export compliance should decide between declaring `false` and
declaring the app 5D992.c mass market (which carries an annual
self-classification report to BIS), then add the key. The list above is
what the decision is about; it is not legal advice, and the fact that the
only non-TLS use is at-rest encryption of a local cache with a
platform-held key is the material point to put to whoever decides.

### Releasing an update — version numbers and the force-update gate

One line in `pubspec.yaml` drives every version number:

```yaml
version: 1.0.14+22      # <versionName>+<versionCode>
```

`android/app/build.gradle.kts` sets `versionName = flutter.versionName` and
`versionCode = flutter.versionCode`, so the Android values are derived from it
and cannot drift. There is nothing to edit under `android/`.

**Every** upload to Play needs a `versionCode` (`+22`) higher than the last one
accepted — Play rejects a re-used one. Bump the `versionName` too whenever
users would see a difference.

#### Forcing users onto the new build

`lib/core/services/remote_config_service.dart` compares this build's version
(from `package_info_plus`) against the `app_min_version` row of the
`app_settings` collection. When the build is older, `ForceUpdateGate`
(`lib/core/widgets/force_update_gate.dart`) blocks the whole app behind an
"update required" screen whose button opens `AppConfig.playStoreUrl`.

`app_min_version` is **server-side data, not part of the build.** Shipping a
new APK does not change it; nothing in the release pipeline touches it. Raise
it deliberately, and only for a release people must take (a security fix, a
breaking schema change):

1. Ship the new version to Play **first** and wait until the rollout is live.
   Raising `app_min_version` to a build that is not downloadable yet locks
   every user out of the app with no way forward.
2. Admin panel → **Settings** → set `app_min_version` to the new
   `versionName` (`1.0.15`, never the `+build` suffix) and, optionally,
   `app_min_version_message`.
3. Leave it alone for an ordinary release. The gate is a lockout, not a nudge.

`app_settings.value` is a **string** on this stack, and the `write` Function
refuses a number for it — a setting written as `1.0.15` from the panel is
right, one written as JSON `1` is refused rather than silently coerced
(`cloud-check.mjs` asserts both directions).

iOS has no App Store id yet, so the gate hides its "Update" button there
(`AppConfig`); an iOS user sees the blocking screen with no way to act. Do not
raise `app_min_version` once an iOS build is in users' hands until
`AppConfig` carries an App Store link.

#### Release checklist

- [ ] `version:` bumped in `pubspec.yaml` (build number always increases)
- [ ] `CHANGELOG.md` updated
- [ ] The Appwrite repository secrets are set, or the release is a Supabase
      build (§ 6, *Using `env.json`*)
- [ ] Tag pushed as `v<version>` — the `build-android-release` CI job only
      runs for `refs/tags/v*` and needs the signing secrets from
      `docs/KEYSTORE_SETUP.md`
- [ ] APK/AAB uploaded and rollout live on Play
- [ ] `app_min_version` raised **only if** this release is mandatory

### Before you trust a build — never-tested areas

**A correction.** This section used to say the app had "never been assembled
into an APK in CI". It has: `build-android-debug` runs
`flutter build apk --debug --no-shrink` on every push and pull request and
uploads `app-debug.apk`, and it passes. So the Android half is not
unproven — Gradle, AGP, Kotlin and the JDK agree, the NDK downloads, and
the 25 plugins' `minSdk` floors are compatible in practice rather than only
in a static audit. The claim was written in an environment that could not
build it (`dl.google.com` blocked) and nobody went back to CI to check.

What is genuinely untested is narrower, and `--no-shrink` is the clue to
the first half of it:

- **No release APK has ever been built.** `isMinifyEnabled` and
  `isShrinkResources` are on for release, so **R8 has never run**, and
  `verifyReleaseSigning` has never been exercised. The release job is
  skipped without a `v*` tag — and until the tag trigger was added it could
  not run at all, so this is not an oversight that one tag fixes by
  accident. Do a signed release build well before you need one.
- **Nothing has run on a device.** The Dart half is verified by 843 tests,
  a clean `flutter analyze --fatal-infos --fatal-warnings`, and a full
  product-mode AOT compile (Android arm64 codegen produces a normal 12 MB
  `libapp.so`, the artifact a release APK embeds) — none of which exercises
  a platform channel against a real OS.

Check these first on a real device, in this order — each builds fine and
fails only at runtime:

1. **Biometric login.** `LaunchTheme`/`NormalTheme` inherit from
   `@android:style/Theme.Light.NoTitleBar`, a plain framework theme rather than
   an AppCompat/Material one. With `FlutterFragmentActivity` and `local_auth`'s
   `BiometricPrompt` this is a known source of `InflateException` at the moment
   the fingerprint sheet appears. If it throws, give the themes a
   `Theme.AppCompat`/`Theme.Material3` parent.
2. **What R8 does to it.** The release build minifies and shrinks
   resources; the debug build CI runs passes `--no-shrink`, so nothing has
   ever been through R8. A rule that keeps too little shows up as a
   `ClassNotFoundException` at runtime, not as a build failure — and the
   ProGuard file's `com.google.gson.**` keep rule matches no class in this
   app, so do not read it as cover. `verifyReleaseSigning` also blocks a
   release build without `android/key.properties`
   (`docs/KEYSTORE_SETUP.md`), which is the other half nobody has run.
3. **Push, on this stack, end to end.** The device registers an Appwrite push
   target and the server subscribes it to its topics; both halves are tested
   against a server of the test's own, and neither has run against Appwrite
   Cloud with a real provider. § 7 step 2 is the first time it does — and on
   iOS it cannot until `GoogleService-Info.plist` exists (§ 1f), because
   there is no token to register.
4. **Deep links.** `lib/core/services/deep_link_service.dart` listens for
   `cradi://…` and `https://cradi.ng/…` with `app_links` and hands the mapped
   location to `go_router`. The mapping is unit-tested
   (`test/unit/deep_link_service_test.dart`) but has never run on a device.

   **`isSupabaseAuthLink` outlived what it protected.** `locationFor` still
   drops any link carrying `access_token`, `code`, `error`, `error_code` or
   `error_description` — in the query string or the fragment — because
   `supabase_flutter` used to consume those. That package is gone, so
   nothing consumes them now and such a link is silently dropped rather
   than routed. Nothing the app currently sends uses those names, so it
   costs nothing today; it will bite the first `cradi://…?code=…` link
   anybody adds. Deciding whether to delete the filter or keep it is a
   product call, not a cleanup.

   The Android manifest sets `android:autoVerify="true"` for
   `https://cradi.ng`, which needs `https://cradi.ng/.well-known/assetlinks.json`
   published with the **release** signing certificate's SHA-256; on iOS,
   Universal Links need the *Associated Domains* entitlement
   (`applinks:cradi.ng`) and an `apple-app-site-association` file. Without
   those, `https://` links open a browser/chooser instead of the app — the
   `cradi://` scheme works regardless.

On the ProGuard file: the `okhttp3.**` rules do apply — OkHttp arrives
transitively with Sentry and OneSignal — and the `com.google.gson.**` rule
(see item 2) matches nothing.

---

## 7. Post-deploy smoke test

In order, against the live deployment, with at least: one admin account, one
reporter (`user`), and **two** approved `ewm` accounts in the **same ward and
LGA** as the report you are about to file. All accounts must be approved by
the admin first (Admin → Users → Approve), and every device must have opened
the app at least once while signed in — that is when it registers its push
target.

Before you start, add one row under **Admin → Authorities** with
`coverageLga` = the report's LGA and `coverageState` = the report's state, and
a Nigerian phone number you control. Both are picked together from the list,
which is grouped by state: the state is required, and a contact is texted only
for its own state's LGA. The `write` Function enforces it — an authority whose
LGA names no state is refused, which is the Postgres CHECK constraint carried
across by hand because Appwrite has none.

1. **Submit a report.** Reporter account, mobile app → new report in that ward
   / LGA. Expect `reports.status = 'pending'`.
2. **Verification push arrives.** Both `ewm` devices (same ward *and* LGA,
   excluding the reporter) receive **"📋 Verification Request"**. This is the
   `report_created` outbox event, drained by the `worker` Function within a
   minute.
   * Nothing arrived? Work § 8 *Pushes do not arrive* in order — on a first
     deployment the answer is almost always a missing Messaging provider or a
     device that has not registered a target.
3. **Peers verify.** Both `ewm` accounts confirm the report. After the second
   confirmation (`app_settings.minimum_peer_confirmations`, default **2**) the
   status moves `pending → verified` automatically and the reporter gets a
   status push.
4. **Approve in the admin panel.** Admin → Reports → set the report to
   **approved**. This single transition triggers three things at once:
   * the **reporter** gets a generic status push;
   * the **LGA broadcast**: the `lga-<state>-<lga>` topic gets
     **"🚨 Verified Hazard Alert"**;
   * the **authority SMS**: the `authorities` row you created receives
     `EWER ALERT: {SEVERITY} {hazard} reported in {ward}, {lga}. …`.
5. **Confirm the broadcast** on a device in that LGA that is **not** the
   reporter and **not** one of the verifiers.
6. **Confirm the SMS** on the authority phone, then that it was recorded: the
   `sms_deliveries` collection should hold a row for that number with
   `status = 'sent'` and a provider message id. `rejected` means Termii
   refused the number. Nothing at all → the `worker` Function has no
   `TERMII_API_KEY`/`TERMII_SENDER_ID`; `deploy.mjs` prints `SMS: OFF` when it
   deployed without them.
7. **Create a targeted alert.** Admin → Community Alerts → new alert with
   **target state = X** and **target LGA = Y**. The state comes first and is
   required: six LGA names (Bassa, Ifelodun, Irepodun, Nasarawa, Obi,
   Surulere) belong to two states each, so an LGA on its own names no single
   place. The three targetings are: one LGA of one state (`lga-<state>-<lga>`);
   every LGA of one state (`All` + a state → `state-<state>`); and everyone
   (`All`, no state → `all-users`).
   * A device whose profile is in state X / LGA Y **receives** it.
   * A device in a **different** LGA — or the same LGA name in a different
     state, Obi in Benue against Obi in Nasarawa — **does not**.
   * A device whose profile has no `state` is in `all-users` only, and will
     not match a state-scoped alert. That is the same limitation the tag-based
     stack had, for the same reason.
8. **Move a user between LGAs.** Admin → Users → change that device owner's
   state or LGA, then send a new alert to the **old** LGA: the device must
   **not** receive it, and must receive one sent to the new LGA. This is the
   subscription reconciliation, and it is the half of push that cannot be
   checked by sending one message.
9. **Escalation (optional, slow).** File a report and leave it. After
   `app_settings.escalation_timeout_minutes` (default 30) the cron sets
   `escalated = true` and notifies coordinators / project staff with
   **"⏰ Unverified Report Escalated"**.

---

## 8. Rollback and troubleshooting

### Provisioning failed partway

Run it again. `provision.mjs` checks every object before it writes and reports
`created` / `exists` / `updated`, so a resumed run is the normal recovery and
there is no "already exists" cascade to clean up. It never deletes, so nothing
it did is destructive.

* **It stopped and named a quota.** `! stopped at <thing>: the project's plan
  refused it` — nothing after that point would have succeeded either. Either
  the plan needs upgrading or the design needs the fallback (`--single-bucket`
  is the one that exists). `--probe` lists every limit in one run instead of
  one round trip per limit.
* **It reported a column it could not create at the planned size.** That is
  MariaDB's row limit, not the plan's: `extract-schema.mjs` sizes columns to
  fit 65,535 bytes at four bytes per character, and a hand-widened column
  breaks it. See its header comment.
* **An index was refused.** Appwrite caps an index at 767 bytes summed over
  its string columns; the four that need explicit `lengths` have them in
  `plan.mjs`.
* **`verify.mjs` exits non-zero on a project you believe is right.** Read the
  lines: `missing` is a real absence, `unreadable` means the key could not
  read it (a scope is missing from the key, not a provisioning failure), `~`
  is an informational size difference and `?` is something the plan does not
  ask for. Only the first two are problems.

### A Function answers 500 to everything

It has no deployment, or its build failed. Both look identical in the console
to a healthy Function. `verify.mjs` reads the deployment id *and* the build
status for exactly this reason. Re-run `deploy.mjs`, which waits for the
builds and fails loudly if one does not reach `ready`.

If it is deployed and still failing, read the execution logs in the console:
a Function that cannot reach the API back usually has the wrong
`APPWRITE_FUNCTION_API_ENDPOINT` or a key with missing scopes, and
`functions/cradi/src/lib/appwrite.js` names the URL in its error rather than
letting `fetch` throw a bare "fetch failed".

### The admin panel looks broken but is "healthy"

`GET /api/health` is a liveness probe that always returns `{"ok": true}`. If
the panel shows a configuration error, or login silently fails, the
`NEXT_PUBLIC_*` variables were wrong or missing **at build time**. Fix them
and **trigger a new deploy** — a restart re-uses the same bundle.

If the browser reports a CORS error, the panel's origin is not a registered
web platform (§ 1c).

### Everything loads but every list is empty

Suspect labels before data. Appwrite answers a read you have no permission for
with `200 {"total": 0}` — not an error — so an account whose labels do not
match the `read("label:…")` rules on `profiles` and `reports` sees a working
app with nothing in it.

* The first admin was promoted with `set:admin`, which sets the labels as well
  as the row (§ 4)?
* For anyone else: the `/write` route puts an account's labels back in step
  with its profile whenever `role`, `isApproved` or `isDisabled` is in the
  patch — so a change made **through the panel** sets them. A role edited
  directly in the console's table editor never goes through the Function, so
  the row says one thing and the account grants another.
* If the label write itself failed, the Function logged it rather than failing
  the call (the row was already written): look for `WARNING: profile <id> was
  updated but its account labels were not`. Re-apply the same change through
  the panel to retry it.

### Pushes do not arrive

In order, because each step makes the next one meaningful:

1. **Is there a push provider at all?** Console → Messaging → Providers, and
   it must be *enabled*. Without one, Appwrite accepts the message, leaves it
   `processing` and reports success (§ 1d). Check Messaging → Messages for
   the message's state — `processing` long after it was sent is this.
2. **Did the device register a target?** Console → Auth → that user →
   Targets. A device registers on sign-in and whenever the token changes; the
   app logs `Push target registered for <user>` when it did, and
   `Push target registration failed: …` when it did not. No target at all
   usually means no FCM token, which means the Firebase platform config is
   missing — on iOS that is the absent `GoogleService-Info.plist` (§ 1f) and
   the log line is `FCM unavailable on this build (push disabled)`.
3. **Is the target subscribed?** Console → Messaging → Topics → the topic →
   Subscribers. The user's `profiles.pushTopics` is what the server believes
   it subscribed them to; if that is empty while a target exists, the
   subscription call failed — the app calls `sync_push_subscriptions` after
   registering, and the `worker` reconciles on every profile update.
4. **Does the topic exist?** Topics are created when the first device
   belonging in one registers, so an alert aimed at an LGA nobody has
   registered in reaches nobody — correctly, but silently.
5. **Is the event queued?** The `notification_outbox` collection:
   `eventType`, `attempts`, `note`, `processedAt`, `availableAt`.
   * No row → the write event did not fire (the wrong status transition, or
     the report was not `pending` on insert).
   * `processedAt` set with a `note` → the handler ran and found nothing to do
     (e.g. no eligible recipients in that ward/LGA).
   * `attempts` climbing with a `note` → the send is failing and the note says
     why. Backoff is exponential, capped at an hour.
   * `attempts` at **8** → given up (`MAX_ATTEMPTS`). Fix the cause, then set
     `attempts` back to 0 and `availableAt` to now for the stuck rows.
6. **Is the `worker` running at all?** Its schedule is `* * * * *`; the
   console's execution list should show a run a minute. A plan that floors
   cron frequency runs it less often without refusing it, and the drain and
   escalation both assume a minute.
7. **iOS specifically:** a Release build carries `aps-environment:
   production`. A `development` token registered as an Appwrite target fails
   at APNs with nothing visible in the app.

### Authority SMS do not arrive

1. `deploy.mjs` printed `SMS: OFF` → the `worker` has no Termii variables.
   Re-deploy with `TERMII_API_KEY` and `TERMII_SENDER_ID` in the environment.
   Remember it replaces a Function's variables wholesale, so a key typed into
   the console does not survive.
2. The `sms_deliveries` collection is the receipt log. A `claimed` row that
   never became `sent` means the process died mid-send, and that number is
   deliberately skipped rather than risk a double text.
3. The caps: `app_settings.max_sms_per_alert_event` (default 20 per report)
   and `max_sms_per_lga_per_day` (default 50 per state+LGA per Africa/Lagos
   day).
4. Every authority names the state of the LGA it covers and is texted for
   that (state, LGA) only. A report whose `state` is empty therefore matches
   **no** authority and sends nothing — deliberately, because texting the
   wrong state's emergency desk is worse than texting no one. Fix the
   report's state, not the query.
5. Termii's send reply carries a `balance` field that read `0` while the
   account held ₦3,610. Do not read it as the balance; check the Termii
   dashboard.

> **Before sending a real SMS from a script**, read the blast-radius note in
> `HANDOFF.md`: `notifyApproved` texts *every* authority covering the
> report's LGA, and on a live project those are real local-government
> contacts. `infra/appwrite/local/e2e-sms-deployed.mjs` refuses to run unless
> its own row is the only one covering the LGA it uses.

---

## The cutover

This runbook deploys the Appwrite stack. Moving the **existing** system onto
it is a separate, ordered procedure, and the production run has not happened:

* `APPWRITE-MIGRATION.md` **Phase 7** — the export → transform → import →
  reconcile pipeline (`docs/appwrite-spike/migrate/`), proven against a
  fixture. Read the pre-flight requirement before any window opens: Appwrite
  refuses email addresses Postgres stores happily, and those users cannot be
  created at all.
* **Phase 8** — the decommission order, and why nothing should be turned off
  yet. Supabase, the Railway worker, OneSignal and Resend stay up.
* `HANDOFF.md` — what is still owed, including the keys to rotate.
* `CLOUD-VERIFICATION.md` — the verification sequence to run against Cloud,
  which overlaps this runbook's steps 2–3 and goes further.

The two stacks no longer run side by side **in one build**: the Supabase
client was removed, so a current APK talks to Appwrite or to nothing. An
older APK still talks to Supabase, which is what keeps the deployed stack
serving users during the window.

That costs Phase 3's push mitigation. It assumed a build that registered
Appwrite targets *while still on OneSignal*, so tokens would exist on the
day; the current app registers FCM tokens with Appwrite and tells
OneSignal nothing. So devices on an old build are reachable only through
OneSignal and devices on a new one only through Appwrite, with no overlap
until each handset updates. SMS is unaffected and is the announcement
channel that survives the window.

---

## Reference

| Topic | File |
| --- | --- |
| The Supabase stack, still in production | `docs/DEPLOYMENT-SUPABASE.md` |
| Provisioning internals, the tier's measured limits, the commands | `infra/appwrite/README.md` |
| What the two Functions promise their callers | `docs/APPWRITE-FUNCTION-CONTRACTS.md` |
| Verifying a live Cloud project, step by step | `docs/CLOUD-VERIFICATION.md` |
| The migration's full record, phase by phase | `docs/APPWRITE-MIGRATION.md` |
| What is still owed, and the keys to rotate | `docs/HANDOFF.md` |
| A real Appwrite in a container, for local work | `infra/appwrite/local/README.md` |
| Admin panel setup and troubleshooting | `CRADI-Mobile-Admin/SETUP.md` |
| Release signing | `docs/KEYSTORE_SETUP.md` |
| Authority contact data entry | `docs/AUTHORITY_CONTACTS_GUIDE.md` |
| iOS project detail | `ios/README.md` |
