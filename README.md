# EWER Mobile (climate_app)

Early Warning and Emergency Response app for CRADI. Flutter client backed by:

| Piece | Service |
| --- | --- |
| Auth, database, file storage, realtime | **Appwrite** (`infra/appwrite/`) |
| Server jobs — push fan-out, escalation cron, the reconciling sweep, authority SMS | **Appwrite Functions** (`functions/cradi/`) |
| Push and email delivery | **Appwrite Messaging**, over an FCM and an APNs provider; the device token comes from **`firebase_messaging`** (see § 2) |
| Authority SMS | **Termii**, called directly by a Function |
| Crash reporting (optional) | **Sentry** |

Business rules that must not be bypassed — a role only applies once an admin
approves the account, the peer-verification threshold, escalation scheduling,
who may write what — are **not in the app**. They live in:

- **document-level ACLs plus account labels**, which is how a read is
  refused. A label lives on the account, not the row, and the `write`
  Function keeps the two in step;
- the **`client` Function**, for the 14 of 19 collections whose rule an ACL
  cannot express (`docs/APPWRITE-FUNCTION-CONTRACTS.md`);
- the **`worker` Function**, for everything the server does on its own.

> **Appwrite answers a read you have no permission for with `200
> {"total": 0}`, not an error.** A working app showing empty lists is the
> most common misconfiguration on this stack, and it is almost always a
> missing label. Several bugs hid behind it during the migration; if a
> list is empty and nothing looks wrong, suspect permissions before data.

> **Deploying for the first time?** Follow `docs/DEPLOYMENT.md` — the
> end-to-end runbook for the Appwrite stack (console → provision →
> Functions → first admin → Railway admin → app build → smoke test).
>
> **The app itself is Appwrite-only.** The Supabase client code was
> removed, so one build can no longer talk to either — but the Supabase
> *deployment* is still what runs in production and nothing has been
> decommissioned. See *The Supabase stack* at the end,
> `docs/DEPLOYMENT-SUPABASE.md` for its runbook,
> `docs/APPWRITE-MIGRATION.md` for the migration's record and
> `docs/HANDOFF.md` for what is still owed.

## 1. Appwrite project

Everything the project needs, apart from four console steps, is scripted:

```bash
export APPWRITE_ENDPOINT=https://fra.cloud.appwrite.io/v1
export APPWRITE_PROJECT_ID=<project id>
export APPWRITE_API_KEY=<a server API key>
export APPWRITE_DATABASE_ID=<database id>     # or let the plan create `cradi`

node infra/appwrite/provision.mjs --dry-run   # read-only: what it would do
node infra/appwrite/provision.mjs             # 19 collections, their indexes, 2 buckets
node infra/appwrite/verify.mjs                # non-zero on any difference
node infra/appwrite/local/deploy.mjs          # the two Functions
```

`provision.mjs` is idempotent and **never deletes anything** — a column in
the project and not in the plan is reported, not dropped. `infra/appwrite/README.md`
has the detail, including the tier limits that have been measured and the
ones that have not.

The four steps no script does, because each is a decision rather than a
configuration: the project and its **region** (which cannot be changed
afterwards), the **API key**, a **web platform** for every browser origin
(Appwrite refuses an origin it does not know, and it reads as a CORS
error), and the **Messaging providers**. `docs/DEPLOYMENT.md` § 1 walks
through them.

The schema itself is derived, not hand-written: `infra/appwrite/columns.json`
is generated from the Supabase migrations by `extract-schema.mjs`, so the
two cannot silently disagree while both stacks exist.

**The first admin** must be promoted with the admin repo's
`npm run set:admin -- <email>`, which sets the `profiles` row *and* the
account's labels. Setting the row alone leaves a signed-in admin who can
read nothing. Every other account is approved from the panel
(Admin → Users).

## 2. Push notifications

Delivery is **Appwrite Messaging**: the `worker` Function posts to a topic
or a list of user ids, and the message id is derived from the outbox event,
so a double send is refused by the server rather than deduplicated by a
vendor.

Three topics, and a device is in all three that apply to it: `all-users`,
`state-<state>`, `lga-<state>-<lga>`. The LGA topic is state-scoped
because six LGA names exist in two states each — Obi is in both Benue and
Nasarawa.

**The device token comes from `firebase_messaging`.** The app registers
that token as an Appwrite *push target* and asks the server to subscribe
it (`AppwritePushTargets` → `sync_push_subscriptions`). It was OneSignal
until the Appwrite-only change; the token's source moved and nothing else
did, which is what that module was built for.

So push needs Firebase platform configuration, not a define:

| | |
|---|---|
| Android | `android/app/google-services.json`, committed. It is client configuration, designed to ship inside the APK — not a secret — but the repository is public, so the `AIzaSy…` key in it should carry application and API restrictions in the Google Cloud console. |
| iOS | `ios/Runner/GoogleService-Info.plist`, **absent**. Without it `Firebase.initializeApp()` throws, `main.dart` catches it, and push is off on iOS. `NotificationService.isPushAvailable` is what reports that. |

Two console steps are prerequisites, and **both fail silently**: Appwrite
Messaging accepts a message with no enabled provider, answers success and
delivers nothing. An FCM provider (service-account JSON) and an APNs key
have to exist, and their **provider ids** have to reach the app build, or
every device on the project's non-default platform is registered against
a provider that cannot deliver to it.

> **The client also subscribes to FCM topics of its own**
> (`FirebaseMessaging.subscribeToTopic`, in `notification_service.dart`),
> with names like `all-users` and `lga_obi`. **Nothing sends to those.**
> Delivery is Appwrite Messaging → an Appwrite topic → the targets
> subscribed to it, and Appwrite topics are a separate namespace that
> happens to share the string `all-users`. Those calls are inert; read
> `functions/cradi/src/lib/topics.js` for the path that is live.

## 3. Server jobs

There is **no Railway backend service on this stack.** The `worker`
Function is what `backend/` was — the outbox drain, the escalation cron,
the reconciling sweep and the Termii send — on Appwrite's own scheduler
(`* * * * *`, with the sweep checking the clock for its five-minute
cadence).

`backend/` stays in the repository because it is what the Supabase stack
runs in production. It reads and writes Supabase and cannot be pointed at
an Appwrite project.

Two Functions in total, not seven, because that was the plan's limit when
they were written: `client` routes the three a client calls on the
execution's path, `worker` routes the four the server runs on its own by
trigger. `docs/APPWRITE-FUNCTION-CONTRACTS.md` is the contract both
clients are written against.

## 4. App configuration (`env.json`)

Runtime settings are compile-time defines read with `String.fromEnvironment`.

```bash
cp env.example.json env.json   # env.json is git-ignored
```

| Key | Required | Notes |
| --- | --- | --- |
| `APPWRITE_ENDPOINT` | yes | `https://<region>.cloud.appwrite.io/v1` — **must end in `/v1`** |
| `APPWRITE_PROJECT_ID` | yes | public; access is enforced by permissions and the Functions |
| `APPWRITE_DATABASE_ID` | if not `cradi` | note: a define that is *present but empty* beats the default |
| `APPWRITE_FN_CLIENT` | no | the client Function's id; defaults to `client` |
| `APPWRITE_PUSH_PROVIDER_ANDROID` | for push | the FCM provider's id (§ 2) |
| `APPWRITE_PUSH_PROVIDER_IOS` | for push | the APNs provider's id (§ 2) |
| `SENTRY_DSN` | no | crash reporting is disabled when empty |
| `APPWRITE_IMAGE_TRANSFORMS` | no | ask Appwrite's `/preview` for smaller renders; off when unset |
| `PROFILE_IMAGES_BUCKET` / `REPORT_IMAGES_BUCKET` | only on a one-bucket tier | default to the two buckets the plan provisions |

**Appwrite is the only backend.** Without the endpoint and project id the
app starts and behaves as signed out — `backend.dart` hands out
`UnconfiguredDataBackend`/`UnconfiguredAuthBackend` — which is what UI work
and the unit tests use, and what a release must never ship. The release job
fails rather than build one.

`APPWRITE_IMAGE_TRANSFORMS` is a delivery-only optimisation. With it, a
thumbnail is requested from Appwrite at the size it will be drawn
(`/preview?width=…&quality=…`) instead of downloading the full-size
original. It is **off by default** because image transformations are a
plan-gated feature on Appwrite Cloud: where they are not included the
request answers with an error rather than the image, and a broken
thumbnail is worse than a large one. Self-hosted has no such limit.
Leaving it unset changes nothing — the small copy uploaded beside each
photo is still used, which is the bulk of the saving.

Run / build with the file:

```bash
flutter pub get
flutter run --dart-define-from-file=env.json
flutter build apk --release --dart-define-from-file=env.json --no-tree-shake-icons
```

### Which project to point at

There is no shared development Appwrite project, and the Cloud project is
the one being prepared for production — do not develop against it. Run a
real Appwrite locally instead:

```bash
./infra/appwrite/local/up.sh          # Appwrite 1.9.6 on :8090 (API) and :8091 (realtime)
node infra/appwrite/local/bootstrap.mjs
source infra/appwrite/local/.env.local
node infra/appwrite/provision.mjs && node infra/appwrite/local/deploy.mjs
```

`infra/appwrite/local/README.md` has the rest, including the six
end-to-end suites it makes runnable and why the server is pinned to
1.9.6. The Cloud project's endpoint, project id and database id are
recorded in `docs/CLOUD-VERIFICATION.md`.

**No server secret is ever passed to the app** — not in `env.json`, not as
a define, not obfuscated. The Appwrite **API key** bypasses every
permission, including the ACLs that are the access-control design; the
Termii key spends money. Both belong in a Function's variables or a
server environment and nowhere else. The app never sends a push or an SMS
itself; it asks a Function to.

Server-tunable values (peer-confirmation threshold, escalation timeout,
SMS caps, feature flags, minimum app version) are rows in the
`app_settings` collection, and its `value` column is a **string** — the
`write` Function refuses a number for it rather than coercing one.

## Development

```bash
flutter analyze --fatal-infos --fatal-warnings
flutter test
dart format --set-exit-if-changed .          # all three are CI gates
```

| Suite | |
| --- | --- |
| `flutter test` | 795 tests (843 before the Supabase client was removed with its tests) |
| `flutter test test/integration` | needs a live Appwrite and the defines `infra/appwrite/local/prep-dart.mjs` prints |
| `functions/cradi` → `npm test` | 277 tests, no dependencies to install |
| `infra/appwrite/local/e2e*.mjs` | six suites against a real Appwrite |
| `infra/appwrite/cloud-check.mjs` | the behaviour a live Cloud project must also show |

Mocks are generated with `dart run build_runner build --delete-conflicting-outputs`.

Two habits this migration was repeatedly caught by, both worth keeping:

- **A fake built from the code it tests can only confirm the code agrees
  with itself.** Three separate tests passed over real bugs that way.
  Derive the expectation from an independent source — the committed
  schema, the implementation that was in production, the producer
  function. `functions/cradi/test/query-attributes.test.mjs` is the
  pattern.
- **A checker may not treat a failed or ambiguous result as a finding**,
  in either direction. A reconciler that read a `400` as "zero rows" once
  condemned a migration that was correct.

## Building for release

See `docs/KEYSTORE_SETUP.md` for signing. The CI release job (tags `v*`
only) writes `env.json` from repository secrets of the same names as the
keys above, dropping the empty ones, and prints the endpoint it built
against. **It fails the build when `APPWRITE_ENDPOINT` and
`APPWRITE_PROJECT_ID` are not both set**, because that APK would install,
start, and behave as permanently signed out.

```bash
flutter build apk --release --no-tree-shake-icons --dart-define-from-file=env.json
```

## The Supabase stack

Still in production, still deployable, being migrated away from. Nothing
has been decommissioned and nothing should be until the cutover has run
and a week of cross-checking has passed (`docs/APPWRITE-MIGRATION.md`
Phase 8).

**No build of this app talks to it any more.** `supabase_service.dart`
and `supabase_auth_backend.dart` are gone, so the only Supabase client
left is the deployed stack's own: the Railway worker, the admin panel's
history, and the SQL. What follows is where those live, not a thing you
can point an APK at.

| Piece | Where |
| --- | --- |
| Postgres schema, RLS, triggers | `supabase/migrations/`, generated into `supabase/deploy/schema.sql` |
| Server jobs (outbox, escalation cron, `POST /email`) | `backend/`, on Railway — `backend/README.md` |
| Push | OneSignal, targeted by tags that the app no longer sets — any device on a current build is invisible to it |
| Email | Resend |
| Deployment runbook | `docs/DEPLOYMENT-SUPABASE.md` |
| Firebase → Supabase import | `migration/firebase-to-supabase/README.md` |

Its anon key is a public client credential — it only grants what the RLS
policies allow — while the **service role key** bypasses every policy and
is a server secret. Both still matter for as long as that stack is
serving users; neither is read by this app any more.

**The push gap at cutover is now real rather than theoretical.** Phase 3's
mitigation was a build that registered Appwrite targets while still on
OneSignal, so tokens would exist on the day. That build no longer exists:
the current app registers FCM tokens with Appwrite and tells OneSignal
nothing. So every device still on an old build is reachable only by
OneSignal, every device on a new one only by Appwrite, and the two sets
do not overlap until each handset updates. Plan announcements by SMS,
which is unaffected.

## Where things are written down

| | |
| --- | --- |
| Deploying the Appwrite stack | `docs/DEPLOYMENT.md` |
| What the two Functions promise their callers | `docs/APPWRITE-FUNCTION-CONTRACTS.md` |
| The migration, phase by phase, with what each one found | `docs/APPWRITE-MIGRATION.md` |
| What is still owed, and the keys to rotate | `docs/HANDOFF.md` |
| Verifying a live Cloud project | `docs/CLOUD-VERIFICATION.md` |
| Provisioning internals and the measured tier limits | `infra/appwrite/README.md` |
| A real Appwrite in a container | `infra/appwrite/local/README.md` |
| Release signing | `docs/KEYSTORE_SETUP.md` |
| Authority contact data entry | `docs/AUTHORITY_CONTACTS_GUIDE.md` |
| iOS project detail | `ios/README.md` |
| Admin panel | `CRADI-Mobile-Admin/README.md`, `SETUP.md` |
