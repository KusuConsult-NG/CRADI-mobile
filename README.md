# EWER Mobile (climate_app)

Early Warning and Emergency Response app for CRADI. Flutter client backed by:

| Piece | Service |
| --- | --- |
| Auth, Postgres database, file storage, realtime | **Supabase** (`supabase/`) |
| Push notifications | **OneSignal** |
| Server jobs (push fan-out, escalation cron, transactional email) | **Railway** (`backend/`, see `backend/README.md`) |
| Crash reporting (optional) | **Sentry** |

Business rules that must not be bypassed (roles only apply once an admin
approves an account, peer-verification threshold, escalation scheduling,
notifications) live in the database (RLS + triggers in
`supabase/migrations/`) and the Railway backend — not in the app.

> **Deploying for the first time?** Follow `docs/DEPLOYMENT.md` — the
> end-to-end runbook (Supabase → first admin → OneSignal → Railway backend →
> Railway admin → app build → smoke test). The sections below are the reference
> for each piece.

## 1. Supabase project

1. Create a project at <https://supabase.com>.
2. Apply the schema. Either paste
   `supabase/deploy/schema.sql` (all 12 migrations, generated — see
   `supabase/deploy/README.md`) into the dashboard **SQL Editor** on an empty
   project, or, with the
   [Supabase CLI](https://supabase.com/docs/guides/cli) installed:

   ```bash
   supabase login
   supabase link --project-ref <your-project-ref>
   supabase db push
   ```

   Afterwards `public` holds 17 tables, all with RLS enabled.

3. **Authentication → Providers → Email**: keep *Confirm email* on.
4. **Authentication → Email Templates**: the app verifies accounts and resets
   passwords with **6-digit codes**, not links. Make sure these templates
   contain `{{ .Token }}`:
   - *Confirm signup* (account verification, `verifyOTP(type: signup)`)
   - *Reset password* (recovery, `verifyOTP(type: recovery)`)
   - *Change email address* (optional; a link is fine here)
5. **Phone sign-up (optional)**: **Authentication → Providers → Phone**, enable
   it and configure an SMS provider (Twilio, MessageBird, Vonage, Textlocal…;
   for Termii use the *Send SMS* auth hook). The app sends the OTP with
   `signInWithOtp(phone: '+234…')`. The phone option on the registration
   screen is hidden until you set `_phoneAuthEnabled = true` in
   `registration_screen.dart`.
6. **Authentication → Rate Limits / Attack protection**: adjust to taste (the
   app also rate-limits OTP resends locally).
7. Create the first admin: sign up in the app (or add the user under
   **Authentication → Users**), confirm its email, then run
   `scripts/set-admin.mjs` in the admin repo — or, in **Table Editor →
   profiles**, set `role = 'admin'` and `is_approved = true` on that row.
   Approval is refused until Supabase Auth has confirmed the account's email or
   phone. Every other account needs an admin to approve it (Admin → Users).
   Details: `docs/DEPLOYMENT.md` section 2.
8. Storage buckets `report-images` and `profile-images` are created by the
   migration (public read; uploads must be under `<user id>/…`).

## 2. OneSignal

1. Create an app at <https://onesignal.com>.
2. Android: upload the **FCM v1 service-account JSON** in *Settings → Push &
   In-App → Google Android (FCM)*. Google still delivers Android pushes through
   FCM, so OneSignal needs these credentials; the app itself contains no
   Firebase SDK or `google-services.json`.
3. iOS: upload an APNs `.p8` key, and in Xcode add the *Push Notifications*
   capability to the Runner target (Background Modes → Remote notifications is
   already set in `Info.plist`). A Notification Service Extension is only
   needed for rich media / badges.
4. Put the OneSignal **App ID** in `env.json` (below) and the **REST API key**
   on the Railway backend.

The app calls `OneSignal.login(<supabase user id>)` after sign-in, sets tags
`role`, `lga`, `state`, `ward`, `monitoring_zone` (lower-cased, non
`[a-z0-9_]` replaced by `_`) and `OneSignal.logout()` on sign-out. The backend
targets users by these.

## 3. Railway backend

Deploy `backend/` as described in `backend/README.md` (root directory
`backend`, branch `supabase-migration`) and note its public URL (used for
`POST /email`). Step-by-step, including every environment variable:
`docs/DEPLOYMENT.md` section 4.

## 4. App configuration (`env.json`)

Runtime settings are compile-time defines read with `String.fromEnvironment`.

```bash
cp env.example.json env.json   # env.json is git-ignored
```

| Key | Required | Notes |
| --- | --- | --- |
| `SUPABASE_URL` | yes | `https://<ref>.supabase.co` |
| `SUPABASE_ANON_KEY` | yes | anon / publishable key (never the service-role key) |
| `ONESIGNAL_APP_ID` | for push | push is disabled when empty |
| `SENTRY_DSN` | no | crash reporting is disabled when empty |
| `IMAGEKIT_URL_ENDPOINT` | no | ImageKit CDN in front of Supabase Storage; images are fetched straight from Supabase when empty |

`IMAGEKIT_URL_ENDPOINT` is a delivery-only optimisation (no SDK, no
upload-side integration). Set it to an ImageKit URL endpoint, e.g.
`https://ik.imagekit.io/<imagekit_id>`, whose origin is this project's
Supabase Storage public base
(`https://<ref>.supabase.co/storage/v1/object/public/`). The app then
requests `<endpoint>/<bucket>/<object path>?tr=w-…,q-…` so photos are
resized at the edge instead of downloading the full-size original; every
other URL (off-site knowledge-base images, signed URLs) is left untouched.
Leaving it empty changes nothing.

Run / build with the file:

```bash
flutter pub get
flutter run --dart-define-from-file=env.json
flutter build apk --release --dart-define-from-file=env.json --no-tree-shake-icons
```

Without `SUPABASE_URL` / `SUPABASE_ANON_KEY` the app starts but behaves as
signed out (useful for UI work and tests).

### Values for the shared development project

The app has no hardcoded fallbacks: these are pasted into your local
`env.json` (git-ignored) or passed with `--dart-define`.

| Key | Value |
| --- | --- |
| `SUPABASE_URL` | `https://splfkqazwzybityoqmyv.supabase.co` |
| `SUPABASE_ANON_KEY` | `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNwbGZrcWF6d3p5Yml0eW9xbXl2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTAzNjg5MzcsImV4cCI6MjEwNTk0NDkzN30.B3p-MTWYacngdF0uGCxDXZNqL7gxYMQNfKp_6i-7QfQ` |
| `ONESIGNAL_APP_ID` | `2e6f30a8-ef18-4091-9961-e6a6fe862322` |
| `IMAGEKIT_URL_ENDPOINT` | `https://ik.imagekit.io/CRADIEWER` (optional; leave empty to serve from Supabase) |

The ImageKit endpoint is public by nature — it appears in every image URL it
serves. ImageKit's **public API key** is not listed because this integration is
delivery-only: no SDK, no client-side upload, so it is never used. ImageKit's
**private key** must never appear here or in the app.

Before the endpoint does anything useful, add a **storage / web-server origin**
to it in the ImageKit dashboard pointing at
`https://splfkqazwzybityoqmyv.supabase.co/storage/v1/object/public/`. Without
that origin every rewritten URL 404s. Verify with one image:
`https://ik.imagekit.io/CRADIEWER/report-images/<uid>/<file>.jpg` should return
the same picture as the Supabase URL, and adding `?tr=w-320` should return a
smaller one.

Both Supabase values are public client credentials: the anon key only grants what the RLS
policies allow, and the OneSignal app id only identifies the app.

**The OneSignal REST API key is a server secret and must never appear in the
app** — not in `env.json`, not in `AppConfig`, not obfuscated. It lives only in
the Railway backend environment as `ONESIGNAL_REST_API_KEY`
(see `backend/README.md`); the app never sends pushes itself, it asks the
backend to.

Server-tunable values (peer-confirmation threshold, escalation timeout, SMS
caps, feature flags, minimum app version) are rows in the `app_settings`
table.

## Development

```bash
flutter analyze
flutter test
```

Mocks are generated with `dart run build_runner build --delete-conflicting-outputs`.

## Building for release

See `docs/KEYSTORE_SETUP.md` for signing. The CI release job writes
`env.json` from the repository secrets `SUPABASE_URL`, `SUPABASE_ANON_KEY`,
`ONESIGNAL_APP_ID` and `SENTRY_DSN`.

```bash
flutter build apk --release --no-tree-shake-icons --dart-define-from-file=env.json
```
