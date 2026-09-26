# EWER / CRADI — deployment runbook

End-to-end, first-time deployment of the whole system, in dependency order.
Written to be followed with the dashboards open. Every step says what to click,
what to paste and how to check it worked before moving on.

**Repositories** (both on branch `supabase-migration`):

| Repo | Contains |
| --- | --- |
| `KusuConsult-NG/CRADI-mobile` | Flutter app (`lib/`), Node backend (`backend/`), database schema (`supabase/`), Firebase import tool (`migration/firebase-to-supabase/`) |
| `KusuConsult-NG/CRADI-Mobile-Admin` | Next.js admin panel |

**Order matters.** Supabase must exist before anything else; the first admin
must exist before the admin panel is useful; OneSignal keys must exist before
the backend can push; the backend URL must exist before the app is built.

```
1. Supabase schema  →  2. First admin  →  3. OneSignal  →  4. Railway backend
                                                        →  5. Railway admin
                                                        →  6. Mobile app build
                                     (7. optional Firebase import)  →  8. Smoke test
```

### Secret handling — read once

| Secret | Belongs in | Must never be in |
| --- | --- | --- |
| Supabase **service role key** | Railway backend variables, Railway admin variables, your local `.env.local` for `set-admin.mjs` | the Flutter app, any `NEXT_PUBLIC_*` variable, any committed file |
| OneSignal **REST API key** | Railway backend variables only | the Flutter app, the admin panel, any committed file |
| Resend / Termii / Twilio keys | Railway backend variables only | anywhere else |
| Supabase **URL** and **anon key** | anywhere (they are public; access is enforced by RLS) | — |
| OneSignal **App ID** | anywhere (public identifier) | — |

The service role key **bypasses every Row Level Security policy**. Anyone
holding it can read and write every row in the database, including other
users' reports and profiles. It is a server-side secret: Railway environment
variables and nothing else.

---

## 1. Supabase — apply the schema

The project must be **empty**. `supabase/deploy/schema.sql` creates tables,
types, functions, triggers and policies outright, so a second run fails with
"already exists".

1. Open the Supabase dashboard → your project → **SQL Editor** → **New query**.
2. Open `supabase/deploy/schema.sql` from the `CRADI-mobile` repo, select all,
   paste it into the editor, and **Run**.
   * The file is generated from `supabase/migrations/*.sql` (12 migrations, in
     filename order). Do not edit it by hand — see
     `supabase/deploy/README.md` for the generator and the drift check.
   * It runs as `postgres`, which is what the SQL editor uses. It needs that:
     it creates two triggers on `auth.users` and four policies on
     `storage.objects`.
   * It takes a few seconds. The editor runs statement by statement; if a
     statement fails, everything before it has already been applied — see
     *Rollback* at the end.
3. **Verify.** New query, run each of these:

   ```sql
   -- expect 17
   select count(*) from information_schema.tables where table_schema = 'public';

   -- expect 17 rows, every one with rowsecurity = true
   select relname, relrowsecurity
     from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r'
    order by 1;

   -- expect 37 policies in public and 4 on storage.objects
   select schemaname, count(*) from pg_policies
    where schemaname in ('public', 'storage') group by 1;

   -- expect 8 rows (minimum_peer_confirmations = 2, escalation_timeout_minutes = 30, ...)
   select key, value from public.app_settings order by key;

   -- expect 10 seeded hazard guides
   select count(*) from public.knowledge_base;
   ```

   The 17 tables are: `alerts`, `app_settings`, `authorities`, `contacts`,
   `knowledge_base`, `login_history`, `messages`, `ndpa_consents`, `news_links`,
   `notification_outbox`, `profiles`, `reports`, `scheduled_escalations`,
   `sms_deliveries`, `trusted_devices`, `verification_overrides`,
   `verifications`.

4. **Storage buckets — already done.** The init migration inserts them; you do
   **not** create them by hand. Confirm under **Storage**, or:

   ```sql
   select id, public, file_size_limit, allowed_mime_types from storage.buckets order by id;
   ```

   Expect exactly two: `profile-images` and `report-images`, both `public =
   true`, `file_size_limit = 5242880` (5 MB), mime types
   `image/jpeg, image/png, image/webp, image/heic`. Object paths must start with
   the uploader's user id — that is what the storage policies enforce.

5. **Auth settings** (Supabase dashboard → **Authentication**):
   * **Providers → Email**: enabled, *Confirm email* **on**. Accounts cannot be
     approved or promoted to admin until their email or phone is confirmed —
     the `profiles_guard_approval` trigger refuses it.
   * **Email Templates**: the app verifies accounts and resets passwords with
     **6-digit codes**, not links. *Confirm signup* and *Reset password* must
     contain `{{ .Token }}`.
   * Phone sign-up is optional; see the repo `README.md` section 1.

6. **Collect the keys** — dashboard → **Project Settings → API**:
   * **Project URL** → `https://<project-ref>.supabase.co`. Used by everything.
   * **anon / public key** → mobile app (`SUPABASE_ANON_KEY`) and admin panel
     (`NEXT_PUBLIC_SUPABASE_ANON_KEY`). Public.
   * **`service_role` key** (revealed behind a "Reveal" control) →
     `SUPABASE_SERVICE_ROLE_KEY` on the Railway backend and the Railway admin
     service. **This key bypasses all Row Level Security.** Never put it in the
     Flutter app, never in a `NEXT_PUBLIC_*` variable, never in a commit.

> `supabase/tests/local_stubs.sql` is **for local Postgres testing only**. Never
> run it against a Supabase project.

---

## 2. Create the first admin

Row Level Security requires an approved admin before the admin panel shows
anything, and the panel cannot create the first one. Chicken-and-egg: sign up
like a normal user, then promote that row.

1. **Sign up.** Either in the mobile app (once it is built, step 6), or
   directly in the dashboard → **Authentication → Users → Add user** with
   *Auto Confirm User* ticked, or by letting the admin panel's login page sit
   idle and signing up in the app first. A `profiles` row is created
   automatically by the `on_auth_user_created` trigger.
2. **Confirm the email.** The account must have `email_confirmed_at` or
   `phone_confirmed_at` set. If you created the user from the dashboard with
   *Auto Confirm*, it already is. Otherwise, click the link/enter the code.
3. **Promote.** Preferred path, from the `CRADI-Mobile-Admin` repo on your own
   machine:

   ```bash
   cd CRADI-Mobile-Admin
   cp .env.example .env.local     # fill in URL, anon key, service role key
   npm install
   node --env-file=.env.local scripts/set-admin.mjs admin@example.org
   ```

   It looks the user up by exact email, refuses ambiguous matches, **refuses an
   account that has not confirmed its email or phone**, sets
   `role = 'admin', is_approved = true, is_disabled = false` on the `profiles`
   row and clears any Auth ban. It needs `SUPABASE_SERVICE_ROLE_KEY` (or the
   `NEXT_PUBLIC_SUPABASE_URL` / `SUPABASE_URL` pair) — run it from a trusted
   machine only, and delete `.env.local` when you are done if the machine is
   shared.

4. **SQL fallback** — if you cannot run Node, paste this into the SQL editor:

   ```sql
   update public.profiles
      set role = 'admin', is_approved = true, is_disabled = false
    where email = 'admin@example.org'
   returning id, email, role, is_approved, is_disabled;
   ```

   It must return exactly one row. Notes:
   * The `profiles_guard` trigger only blocks privilege changes when
     `auth.uid()` is non-null (i.e. a client session). The SQL editor has no
     session, so this update is allowed.
   * `profiles_guard_approval` still applies: if it raises *"This account has
     not confirmed its email or phone yet"*, confirm the account first
     (dashboard → **Authentication → Users → … → Confirm email**).
   * If it returns 0 rows, the profile does not exist — the user never signed
     up, or signed up before the schema was applied. Delete and re-create the
     Auth user so the trigger fires.

5. Every other account needs this admin to approve it: **Admin panel → Users →
   Approve**. Unapproved roles grant nothing (`public.app_role()` returns the
   role only for approved, non-disabled accounts).

---

## 3. OneSignal

### 3a. Rotate the leaked REST API key — do this first

The existing OneSignal REST API key for app
`2e6f30a8-ef18-4091-9961-e6a6fe862322` was exposed publicly and must be
considered compromised: anyone holding it can send push notifications to every
user of the app.

1. OneSignal dashboard → your app → **Settings → Keys & IDs**.
2. Delete / revoke the existing **App API Key** (REST API key).
3. Create a new one. Copy it **once** — you will paste it into Railway in step
   4 and nowhere else.
4. Do not commit it, do not put it in `env.json`, do not paste it into a chat
   or an issue. If it leaks again, repeat this step.

### 3b. Collect the App ID

Same page, **App ID**: `2e6f30a8-ef18-4091-9961-e6a6fe862322`. This one is a
public identifier — it goes into the Flutter build (`ONESIGNAL_APP_ID`) *and*
into the backend.

### 3c. Platform credentials

* **Android**: *Settings → Push & In-App → Google Android (FCM)* — upload the
  **FCM v1 service-account JSON**. Google still delivers Android pushes through
  FCM; the credentials live inside OneSignal only. The Flutter app contains no
  Firebase SDK and no `google-services.json`.
* **iOS**: upload an APNs `.p8` key, and in Xcode add the *Push Notifications*
  capability to the Runner target.

### 3d. Android notification channel (optional)

If you want a dedicated high-importance channel: *Settings → Android
Categories* → create one (e.g. "Alerts") and copy its id into the backend as
`ONESIGNAL_ANDROID_CHANNEL_ID`. It **must be a UUID**: the backend validates it
and, if it is not, logs `config.onesignal_channel_invalid` and ignores it
(OneSignal rejects every push naming an unknown channel, so a typo would
silently break all Android pushes). Leave it empty if unsure.

### 3e. Identity Verification

Without it, any device can call `OneSignal.login(<someone else's uuid>)` or set
any `lga` tag and receive that user's pushes. This is why every push body in
this system is generic (ids and an event `type` only). Enabling Identity
Verification (*Settings → Keys & IDs*) requires a follow-up change in the app
(a server-issued JWT per external id) — see `backend/README.md`. Do not enable
it until that exists, or sign-in will break push delivery.

**Where the REST key goes:** Railway backend service variables, as
`ONESIGNAL_REST_API_KEY`. Nowhere else.

---

## 4. Railway — backend service

Source: `KusuConsult-NG/CRADI-mobile`, branch `supabase-migration`, **root
directory `backend`**.

1. Railway → **New Project → Deploy from GitHub repo** → `KusuConsult-NG/CRADI-mobile`.
2. Service → **Settings → Source**:
   * **Root Directory** = `backend`
   * **Branch** = `supabase-migration`
3. Railway then picks up `backend/railway.json`: Dockerfile build
   (`backend/Dockerfile`, Node 22 Alpine, `npm ci --omit=dev`), start command
   `node src/index.js`, healthcheck `GET /health` with a 60 s timeout, restart
   `ON_FAILURE` up to 10 times. You do not set a build or start command by hand.
4. Service → **Variables**. All 18 variables from `backend/.env.example`:

   | Variable | Required? | Default | Notes |
   | --- | --- | --- | --- |
   | `SUPABASE_URL` | **required** | — | `https://<project-ref>.supabase.co` (step 1.6) |
   | `SUPABASE_SERVICE_ROLE_KEY` | **required** | — | Service role key (step 1.6). Bypasses RLS. |
   | `ONESIGNAL_APP_ID` | for push | — | Step 3b. Unset → pushes are logged and skipped. |
   | `ONESIGNAL_REST_API_KEY` | for push | — | The **rotated** key from step 3a. Unset → pushes skipped. |
   | `ONESIGNAL_ANDROID_CHANNEL_ID` | no | — | Must be a UUID or it is ignored (step 3d). |
   | `RESEND_API_KEY` | for email | — | Unset → `POST /email` returns 503. |
   | `FROM_EMAIL` | no | `noreply@cradi.ng` | Must be on a domain verified in Resend. |
   | `FROM_NAME` | no | `EWER Alert System` | |
   | `SMS_PROVIDER` | for SMS | — | `termii` or `twilio`. Unset/unknown → authority SMS logged and skipped. |
   | `TERMII_API_KEY` | if `termii` | — | |
   | `SMS_SENDER_ID` | if `termii` | — | Registered Termii sender ID (the `from`). |
   | `TWILIO_ACCOUNT_SID` | if `twilio` | — | |
   | `TWILIO_AUTH_TOKEN` | if `twilio` | — | |
   | `TWILIO_FROM` | if `twilio` | — | Sending number in E.164. |
   | `PORT` | no | `8080` | Railway sets this for you. |
   | `WORKER_POLL_MS` | no | `5000` | Outbox poll interval. |
   | `ESCALATION_POLL_MS` | no | `60000` | Escalation cron interval. |
   | `CORS_ORIGINS` | no | empty | Comma-separated browser origins allowed to call `POST /email`, or `*`. The mobile app needs none. |

   **Only `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are hard requirements**
   (`REQUIRED` in `backend/src/config.js`). If either is missing:
   `src/index.js` logs `config.missing_required`, does **not** start the outbox
   worker or the escalation cron, and `/health` returns **503** — which makes
   Railway's healthcheck fail and the deploy fail. Every other variable only
   degrades a feature and logs a warning (`config.onesignal_missing`,
   `config.sms_missing`, `config.resend_missing`).

   A partial SMS provider config counts as unconfigured: `smsConfigured()`
   requires `TERMII_API_KEY` **and** `SMS_SENDER_ID` for `termii`, or all three
   Twilio values for `twilio`.

5. **Settings → Networking → Generate Domain.** Note the URL, e.g.
   `https://cradi-backend.up.railway.app` — the Flutter app needs it as
   `BACKEND_URL` in step 6.
6. **Verify:**

   ```bash
   curl -i https://<your-backend>.up.railway.app/health
   ```

   Expect **HTTP 200** and a body like:

   ```json
   {
     "ok": true,
     "config": { "supabase": true, "onesignal": true, "resend": true, "sms": true },
     "workers": {
       "outbox":      { "lastRunAt": "...", "lastSuccessAt": "...", "stale": false, "healthy": true },
       "escalations": { "lastRunAt": "...", "lastSuccessAt": "...", "stale": false, "healthy": true }
     }
   }
   ```

   * `ok: false` with **503** → a required variable is missing.
   * `workers` is `{}` → the worker and cron did not start, which only happens
     when Supabase config is missing.
   * A `config` flag is `false` → that integration is disabled but the service
     is otherwise healthy.

   In **Deploy Logs** the line to look for at start-up is:

   ```
   {"level":"info","event":"server.listening","port":8080,"config":{...},"workerPollMs":5000,"escalationPollMs":60000}
   ```

   The loops do not log on start — they log only on failure
   (`outbox.tick_failed`, `escalations.tick_failed`). Their liveness is visible
   in the `workers` block of `/health`, which is the thing to watch: a loop is
   `healthy: false` when its last tick threw, and `stale: true` when it has not
   completed a tick for more than 5× its poll interval.

   One replica is enough. Several are safe (outbox rows are claimed with
   `FOR UPDATE SKIP LOCKED`, every push carries an idempotency key).

### The worker must stay running

This service is not a website that can sleep between visitors. It polls for new
reports every `WORKER_POLL_MS` (5 s) and for overdue escalations every
`ESCALATION_POLL_MS` (60 s). If the container is suspended, evicted, or stopped
because a trial credit ran out, the system fails **silently and in the worst
direction**: the app keeps accepting reports and the admin panel keeps working,
but no verification request, approval broadcast, authority SMS or escalation
ever goes out. Nobody sees an error — the queue simply grows.

Two consequences worth planning for:

* **Check the plan, not just the deploy.** A free or trial tier that sleeps idle
  services, or that expires after a credit, will stop the worker without
  stopping anything else. Confirm the service is set to run continuously.
* **Watch `/health` from outside Railway.** Point any uptime monitor at
  `GET /health` (the free tier of any of them is enough) and alert on a non-200
  or on `workers.*.stale = true`. That turns a silent failure into a message.

Nothing is lost while the worker is down — `notification_outbox` rows stay
queued and are delivered when it comes back, subject to their retry backoff
(8 attempts). But an early-warning notification delivered hours late is not an
early warning. Treat a stopped worker as an outage.

---

## 5. Railway — admin panel service

Source: `KusuConsult-NG/CRADI-Mobile-Admin`, branch `supabase-migration`, root
directory = repository root.

> ### `NEXT_PUBLIC_*` values are baked in at BUILD time
>
> `lib/supabase.ts` and `lib/csp.ts` read `NEXT_PUBLIC_SUPABASE_URL` and
> `NEXT_PUBLIC_SUPABASE_ANON_KEY` through `process.env`, and Next.js **inlines
> them into the compiled bundle during `npm run build`**. Setting them after the
> first build does nothing until you redeploy.
>
> The failure is silent: `GET /api/health` returns `{"ok": true}`
> unconditionally, so **Railway's healthcheck passes on a completely broken
> app**. You get a "Configuration required" screen instead of the login page (and,
> if only the URL is wrong, a Content-Security-Policy that blocks every request
> to Supabase, so login fails with nothing obvious in the UI).
>
> **Set both `NEXT_PUBLIC_*` variables before the first deploy. If you change
> either one later, trigger a fresh deploy — a restart is not enough.**

1. In the same Railway project (or a new one): **New → GitHub Repo** →
   `KusuConsult-NG/CRADI-Mobile-Admin`.
2. Service → **Settings → Source → Branch** = `supabase-migration`. Leave the
   root directory at the repository root.
3. `railway.json` configures the rest: **Nixpacks** builder, build command
   `npm run build`, start command `npm start` (`next start -p ${PORT:-3000}`,
   so it binds Railway's `$PORT`), healthcheck `GET /api/health` with a 100 s
   timeout, restart `ON_FAILURE` up to 10 times. Node 22+ is required
   (`engines` in `package.json`).
4. Service → **Variables** — three, all of them needed:

   | Variable | Required? | When it is read | Notes |
   | --- | --- | --- | --- |
   | `NEXT_PUBLIC_SUPABASE_URL` | **required** | **build time** (inlined) | `https://<project-ref>.supabase.co`. Also becomes the `connect-src` / `img-src` origin in the CSP. |
   | `NEXT_PUBLIC_SUPABASE_ANON_KEY` | **required** | **build time** (inlined) | Public anon key. Access enforced by RLS. |
   | `SUPABASE_SERVICE_ROLE_KEY` | **required in practice** | runtime (server only) | Used by `/api/admin/users/*` (approve, revoke, role, location, block, delete). Without it those routes return `500 Server is not configured for admin actions.` — everything else still works. Never prefix it with `NEXT_PUBLIC_`. |

   `PORT` is supplied by Railway. There is nothing else to set.

5. **Settings → Networking → Generate Domain.**
6. Optional: add that domain to Supabase → **Authentication → URL
   Configuration** (only needed for auth email redirects; password sign-in
   works without it).
7. **Verify:**
   * `curl https://<your-admin>.up.railway.app/api/health` → `{"ok":true}`
     (liveness only — it proves nothing about configuration).
   * Open the domain in a browser. You must get the **login page**, not a
     "Configuration required" screen. That screen means the
     `NEXT_PUBLIC_*` variables were missing at build time — set them and
     redeploy.
   * Sign in with the admin from step 2. You must land on the **dashboard**
     with counts (users, reports, contacts, knowledge articles, active alerts).
   * *"Access denied. This account is not an approved, active administrator."* →
     step 2 did not take effect for that email.
   * Empty lists with no error → RLS is returning nothing; re-check the
     profile's `role` / `is_approved` / `is_disabled`.

---

## 6. Mobile app build

All runtime configuration is compile-time (`String.fromEnvironment`) in
`lib/core/constants/app_config.dart`. There are **five** defines:

| `--dart-define` key | Required? | Value | Effect when empty |
| --- | --- | --- | --- |
| `SUPABASE_URL` | **yes** | `https://<project-ref>.supabase.co` | With either Supabase value empty, `AppConfig.isSupabaseConfigured` is false and the app starts permanently signed out (useful for UI work and tests). |
| `SUPABASE_ANON_KEY` | **yes** | anon / publishable key | as above |
| `ONESIGNAL_APP_ID` | for push | `2e6f30a8-ef18-4091-9961-e6a6fe862322` | push is disabled |
| `BACKEND_URL` | for email | the Railway backend URL from step 4.5, **no trailing slash** | transactional email from the app is unavailable |
| `SENTRY_DSN` | no | Sentry DSN | crash reporting disabled |

`AppConfig` also holds non-configurable constants (the Android
`applicationId`, the Play Store URL, table names and the two storage bucket
names) — nothing to set there.

### Using `env.json`

```bash
cp env.example.json env.json     # env.json is git-ignored
# edit env.json: SUPABASE_URL, SUPABASE_ANON_KEY, ONESIGNAL_APP_ID, BACKEND_URL, SENTRY_DSN
flutter pub get
flutter run   --dart-define-from-file=env.json
flutter build apk --release --no-tree-shake-icons --dart-define-from-file=env.json
```

`env.example.json` is the template and contains only placeholders. The CI
release job writes `env.json` from the repository secrets `SUPABASE_URL`,
`SUPABASE_ANON_KEY`, `ONESIGNAL_APP_ID`, `BACKEND_URL` and `SENTRY_DSN`.
Signing: see `docs/KEYSTORE_SETUP.md`.

> **The OneSignal REST API key must never be passed to the app** — not in
> `env.json`, not as a `--dart-define`, not in `AppConfig`, not obfuscated.

### Before you trust a build — never-tested areas

The app has been compiled but **never assembled into an APK in CI or run on a
device**. The Dart half is verified: a full product-mode AOT compile of
`lib/main.dart` with every package succeeds, and Android arm64 codegen produces
a normal 12 MB `libapp.so` — the exact artifact a release APK embeds. The
Android/Gradle half could not be built here (the environment blocks
`dl.google.com`, so no SDK, NDK or Android Gradle Plugin). A static audit found
the Gradle/AGP/Kotlin/JDK versions coherent and no `minSdk` conflict across the
25 Android plugins (all need ≤ 24; the app sets 24).

Check these first on a real device, in this order — each compiles fine and
fails only at runtime:

1. **Biometric login.** `LaunchTheme`/`NormalTheme` inherit from
   `@android:style/Theme.Light.NoTitleBar`, a plain framework theme rather than
   an AppCompat/Material one. With `FlutterFragmentActivity` and `local_auth`'s
   `BiometricPrompt` this is a known source of `InflateException` at the moment
   the fingerprint sheet appears. If it throws, give the themes a
   `Theme.AppCompat`/`Theme.Material3` parent.
2. **A release build at all.** `isMinifyEnabled` and `isShrinkResources` are on,
   and `verifyReleaseSigning` blocks release builds without
   `android/key.properties` (see `docs/KEYSTORE_SETUP.md`). R8 has therefore
   never run. Do a signed release build well before you need one.
3. **The NDK.** `jni` is among the plugins, so `ndkVersion` 28.2.13676358 is
   genuinely required — a ~2 GB download on the first Android build.
4. **Deep links.** The manifest sets `android:autoVerify="true"` for
   `https://cradi.ng`, which needs `https://cradi.ng/.well-known/assetlinks.json`
   published with the **release** signing certificate's SHA-256. Without it,
   links open a chooser dialog instead of the app.

Known-harmless cruft, listed so nobody reads it as protection: the ProGuard
rules for `hive.**`, `com.google.gson.**` and `okhttp3.**` match no Java class
in this app (Hive is pure Dart and lives inside `libapp.so`; the OkHttp comment
still says "used by Appwrite"), and `android.enableJetifier=true` is deprecated
under AGP 8 and only slows builds.

> Anything compiled into an APK can be extracted from it. The app never sends a
> push itself; it asks the backend to. The REST key lives only in the Railway
> backend environment. The same rule applies to the Supabase **service role
> key** and any SMS/Resend credential.

---

## 7. Firebase data import (optional)

Only if you are bringing data over from the old Firebase project. Full
procedure, flags and failure modes: **`migration/firebase-to-supabase/README.md`**.

The one rule that cannot be broken:

> **The Railway backend must stay stopped from the first `--apply` run until
> the last one.** In Railway, scale the backend service to **0 replicas** (or
> remove its active deployment) before the first `--apply`, and scale it back up
> only after the final run.

Imported reports and status changes fire the same database triggers as live
ones, so a running backend would push years of historical events to real users'
phones within seconds. The importer refuses `--apply` unless you also pass
`--i-stopped-the-backend`, and it suppresses the outbox rows it creates — but
that suppression happens at the end of a run, so a run killed in the middle
leaves events a later run will not suppress. Hence: backend down for the whole
import, up again afterwards.

Back up the importer's state file after each `--apply` run; without it a re-run
re-inserts instead of upserting.

---

## 8. Post-deploy smoke test

Do this in order, against the live deployment, with at least: one admin
account, one reporter account (`user`), and **two** approved `ewm` accounts in
the **same ward and LGA** as the report you are about to file. All accounts
must be approved by the admin first (Admin → Users → Approve).

Before you start, add one row under **Admin → Authorities** with
`coverage_lga` = the report's LGA and `coverage_state` = the report's state,
and a Nigerian phone number you control.

1. **Submit a report.** Reporter account, mobile app → new report in that ward
   / LGA. Expect `reports.status = 'pending'`.
2. **Verification push arrives.** Both `ewm` devices (same ward *and* LGA,
   excluding the reporter) receive **"📋 Verification Request"**. This is the
   `report_created` outbox event handled by the backend worker.
   * Nothing arrived? `select * from public.notification_outbox where processed_at is null order by created_at desc;`
     and check the backend logs.
3. **Peers verify.** Both `ewm` accounts confirm the report. After the second
   confirmation (`app_settings.minimum_peer_confirmations`, default **2**) the
   status moves `pending → verified` automatically and the reporter gets a
   status push.
4. **Approve in the admin panel.** Admin → Reports → set the report to
   **approved**. This single transition is what triggers three things at once:
   * the **reporter** gets a generic status push;
   * the **LGA broadcast**: every device tagged with that LGA (and, since the
     report has a state, also tagged with that state) gets
     **"🚨 Verified Hazard Alert"**;
   * the **authority SMS**: the `authorities` row you created receives
     `EWER ALERT: {SEVERITY} {hazard} reported in {ward}, {lga}. …`.
5. **Confirm the broadcast** on a device tagged with that LGA that is **not**
   the reporter and **not** one of the verifiers.
6. **Confirm the SMS** on the authority phone. Then check it was recorded:

   ```sql
   select phone, status, created_at from public.sms_deliveries order by created_at desc limit 5;
   ```

   Expect a `sent` row. `rejected` means the provider refused the number.
   Nothing at all → `SMS_PROVIDER` or its credentials are incomplete; the
   backend logs `sms.skipped_not_configured`.
7. **Create a targeted alert.** Admin → Community Alerts → new alert with
   **target state = X** and **target LGA = Y**.
   * A device whose profile is in state X / LGA Y **receives** it.
   * A device in a **different** LGA (or the same LGA name in a different
     state — e.g. Obi in Benue vs Obi in Nasarawa) **does not**.
   * *Known limitation:* a device with no `state` tag (an old build, or a
     profile with no state) will not match a state-scoped alert. Test with a
     current build.
8. **Escalation (optional, slow).** File a report and leave it. After
   `app_settings.escalation_timeout_minutes` (default 30) the cron sets
   `escalated = true` and notifies coordinators / project staff with
   **"⏰ Unverified Report Escalated"**.

---

## 9. Rollback and troubleshooting

### The schema run failed partway

The SQL editor applies statement by statement, so the objects created before
the failing statement are still there. Do **not** re-run `schema.sql` on top —
you will get a cascade of "already exists".

* **Cleanest fix:** Supabase dashboard → **Settings → General → Reset
  database** (destroys all data), then run `schema.sql` again from the top.
* **If you cannot reset** (there is data you need), drop only what was created
  and start over:

  ```sql
  -- destructive; removes the whole application schema
  drop schema public cascade;
  create schema public;
  grant usage on schema public to anon, authenticated, service_role;
  grant all on schema public to postgres;
  -- then clean up the objects that live outside public:
  drop trigger if exists on_auth_user_created on auth.users;
  drop trigger if exists on_auth_user_updated on auth.users;
  drop policy if exists "users upload own images"          on storage.objects;
  drop policy if exists "users read own images"            on storage.objects;
  drop policy if exists "users update own profile images"  on storage.objects;
  drop policy if exists "users delete own profile images"  on storage.objects;
  delete from storage.buckets where id in ('report-images', 'profile-images');
  ```

  then run `schema.sql` again. Note that dropping `public` also drops the
  default privileges Supabase sets on it, so PostgREST may need
  `notify pgrst, 'reload schema';` afterwards. Prefer **Reset database** when
  you can.
* **Before touching production again**, reproduce the failure locally — see
  `supabase/deploy/README.md` for the plain-Postgres procedure. The file is
  verified to apply cleanly to an empty database, so a failure means the
  project was not empty, or the SQL editor's statement splitting choked on a
  paste (try running it in a single paste, not in pieces).

### Railway backend healthcheck fails

1. **Deploy Logs**: look for `config.missing_required`. It names the missing
   variables. Only `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` can cause
   this. Add them → redeploy.
2. No such line, but the healthcheck still times out: check the service is
   listening. The start log is `server.listening` with `"port": 8080`. Railway
   injects `PORT`; do not hard-code a different one.
3. `/health` returns 503 with `ok: false` → same as (1); the `config` block
   shows which integration is missing.
4. Build failed before that: the root directory must be `backend` so Railway
   finds `backend/railway.json` and `backend/Dockerfile`. If it tried Nixpacks
   at the repo root, the root directory is wrong.
5. Crash loop (`restartPolicyMaxRetries: 10` exhausted): look for
   `process.unhandled_rejection` in the logs.

### Railway admin panel looks broken but is "healthy"

`/api/health` is a liveness probe that always returns `{"ok": true}`. If the
panel shows a configuration error, or login silently fails, the `NEXT_PUBLIC_*`
variables were wrong or missing **at build time**. Fix the variables and
**trigger a new deploy** (Deployments → Redeploy). A restart re-uses the same
broken bundle.

### Pushes do not arrive

In order:

1. `curl https://<backend>/health` → is `config.onesignal` `true`? If not,
   `ONESIGNAL_APP_ID` / `ONESIGNAL_REST_API_KEY` are unset on Railway. Pushes
   are logged and skipped, silently.
2. Did the key get rotated (step 3a) without updating Railway? OneSignal will
   reject every request with 401/403 — the backend logs it and the outbox rows
   retry with backoff.
3. Is the event queued at all?

   ```sql
   select id, event_type, attempts, last_error, processed_at, available_at
     from public.notification_outbox
    order by created_at desc limit 20;
   ```

   * No row → the database trigger did not fire (wrong status transition, or
     the report was not `pending` on insert).
   * Row with `processed_at` set and a note in `last_error` → the worker ran
     and found nothing to do (e.g. no matching recipients in that ward/LGA).
   * Row with `attempts` climbing and `last_error` set → the send is failing;
     `last_error` says why.
4. Stuck for good — 8 attempts is the cap:

   ```sql
   select * from public.notification_outbox where processed_at is null and attempts >= 8;
   ```

   Fix the cause, then reset them: `update public.notification_outbox set attempts = 0, available_at = now() where processed_at is null;`
5. Targeting: the app sets OneSignal tags `role`, `lga`, `state`, `ward`,
   `monitoring_zone`, each sanitised as
   `value.toLowerCase().replace(/[^a-z0-9_]/g, '_')` ("Obio/Akpor" →
   `obio_akpor`). A profile with an empty `lga`, or a device that has not
   signed in since the tag was introduced, matches nothing. Check the device in
   the OneSignal dashboard (Audience → Subscriptions → its external id).
6. Android specifically: `ONESIGNAL_ANDROID_CHANNEL_ID` must be a UUID of a
   channel that exists, or OneSignal rejects the push. Look for
   `config.onesignal_channel_invalid` in the logs; clear the variable to fall
   back to the default channel.

### Authority SMS do not arrive

`config.sms` in `/health` must be `true`. Then check `public.sms_deliveries`
(service role only — query it from the SQL editor): a `claimed` row that never
became `sent` means the process died mid-send, and that number is deliberately
skipped rather than risk a double text. Also check the caps:
`app_settings.max_sms_per_alert_event` (default 20 per report) and
`max_sms_per_lga_per_day` (default 50 per state+LGA per Africa/Lagos day).

An authority row with `coverage_state` NULL is a legacy row that matches every
same-named LGA in any state; edit it in the admin panel and pick the state.

---

## Reference

| Topic | File |
| --- | --- |
| Schema generator, local verification, what `local_stubs.sql` fakes | `supabase/deploy/README.md` |
| Backend internals: outbox, escalation cron, SMS, `/email` API, OneSignal contract | `backend/README.md` |
| App configuration and Supabase auth settings | `README.md` |
| Admin panel setup and troubleshooting | `CRADI-Mobile-Admin/SETUP.md` |
| Firebase → Supabase import | `migration/firebase-to-supabase/README.md` |
| Release signing | `docs/KEYSTORE_SETUP.md` |
| Authority contact data entry | `docs/AUTHORITY_CONTACTS_GUIDE.md` |
