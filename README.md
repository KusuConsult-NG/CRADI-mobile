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

## 1. Supabase project

1. Create a project at <https://supabase.com> and install the
   [Supabase CLI](https://supabase.com/docs/guides/cli).
2. Apply the schema:

   ```bash
   supabase login
   supabase link --project-ref <your-project-ref>
   supabase db push
   ```

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
7. Create the first admin: sign up in the app, then in **Table Editor →
   profiles** set `role = 'admin'` and `is_approved = true` on that row.
   Every other account needs an admin to approve it (Admin → Users).
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

Deploy `backend/` as described in `backend/README.md` and note its public URL
(used for `POST /email`).

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
| `BACKEND_URL` | for email | Railway URL, no trailing slash |
| `SENTRY_DSN` | no | crash reporting is disabled when empty |

Run / build with the file:

```bash
flutter pub get
flutter run --dart-define-from-file=env.json
flutter build apk --release --dart-define-from-file=env.json --no-tree-shake-icons
```

Without `SUPABASE_URL` / `SUPABASE_ANON_KEY` the app starts but behaves as
signed out (useful for UI work and tests).

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
`ONESIGNAL_APP_ID`, `BACKEND_URL` and `SENTRY_DSN`.

```bash
flutter build apk --release --no-tree-shake-icons --dart-define-from-file=env.json
```
