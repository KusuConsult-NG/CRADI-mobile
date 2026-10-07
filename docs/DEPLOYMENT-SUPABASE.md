# EWER / CRADI — deployment runbook (Supabase stack)

> **This is the stack that is in production, and the one being migrated
> away from.** It is kept, unchanged apart from this note, because nothing
> has been decommissioned and nothing should be until the Appwrite cutover
> is done and a week of cross-checking has passed (Phase 8 in
> `APPWRITE-MIGRATION.md`). If you are fixing the system that is live
> today — Supabase, the Railway worker, OneSignal, Resend — this is the
> runbook.
>
> **For a new deployment, use `DEPLOYMENT.md`**, which deploys the Appwrite
> stack the app and the admin panel are now written against. The two
> overlap only in the mobile build, iOS and release sections, and
> `DEPLOYMENT.md` carries the current version of those.

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

   The 21 tables are: `alerts`, `alerts_unresolved_target`, `app_settings`,
   `authorities`, `authorities_unresolved_coverage`, `contacts`,
   `knowledge_base`, `login_history`, `messages`, `ndpa_consents`,
   `news_links`, `nigeria_lgas`, `nigeria_states`, `notification_outbox`,
   `profiles`, `reports`, `scheduled_escalations`, `sms_deliveries`,
   `trusted_devices`, `verification_overrides`, `verifications`.

   `nigeria_states` (37 rows) and `nigeria_lgas` (770 rows) are canonical
   reference data, read-only to clients. The two `*_unresolved_*` tables are
   empty on a fresh project; they only ever hold rows that migrations
   `20260927080000` / `20260927090000` had to set aside — see
   [Authority SMS do not arrive](#authority-sms-do-not-arrive) below.

4. **Storage buckets — already done.** The init migration inserts them; you do
   **not** create them by hand. Confirm under **Storage**, or:

   ```sql
   select id, public, file_size_limit, allowed_mime_types from storage.buckets order by id;
   ```

   Expect exactly two: `profile-images` and `report-images`, both `public =
   true`, `file_size_limit = 5242880` (5 MB), mime types
   `image/jpeg, image/png, image/webp, image/heic`. Object paths must start with
   the uploader's user id — that is what the storage policies enforce.

5. **Auth settings** — every one of them is listed in **section 1a** below.
   Work through that checklist now; auth does not work with the dashboard
   defaults.

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

## 1a. Auth configuration — the complete checklist

Supabase ships with defaults that **do not work for this app**: the Site URL is
`http://localhost:3000` and every email template sends a *link*, while the
mobile app asks the user to type a **6-digit code**. That mismatch is why a
recovery mail can arrive perfectly (SMTP fine) and still be useless.

Password recovery is the one flow with **two audiences**: the mobile app needs
the 6-digit code, and the admin panel now has a browser page at
`/reset-password`. The **Reset Password** template in section *d* below carries
both, so one mail serves both. Do not trim it down to one half.

### What each flow actually needs

| Flow | App entry point | Sends to Supabase | Needs | Email template | Required variable |
| --- | --- | --- | --- | --- | --- |
| Registration (email) | `/register` → `AuthProvider.signUpWithEmail` | `auth.signUp(email, password, data: {name, role, phone, state, lga, ward, address})` | — | — | — |
| Email confirmation | `/verify-otp` → `verifyOtpAndLogin` | `auth.verifyOTP(type: signup, email, token)` | **code** | **Confirm signup** | `{{ .Token }}` |
| Resend confirmation | `/verify-otp`, and automatically after an `email_not_confirmed` login | `auth.resend(type: signup, email)` | **code** | **Confirm signup** | `{{ .Token }}` |
| Sign-in | `/login` | `auth.signInWithPassword(email, password)` | — | — | — |
| Password reset — send | `/forgot-password` (app), or Supabase → Users → *Send password recovery* | `auth.resetPasswordForEmail(email, redirectTo: 'cradi://reset-password')` (the app; the dashboard sends none) | **code + link** | **Reset Password** | `{{ .Token }}` **and** `{{ .ConfirmationURL }}` |
| Password reset — confirm (mobile app) | `/reset-password` in the app | `auth.verifyOTP(type: recovery, email, token)` then `auth.updateUser(password:)` | **code** | **Reset Password** | `{{ .Token }}` |
| Password reset — confirm (link, in the app) | `/reset-password?recovery=1` in the app | `supabase_flutter` consumes the callback → `passwordRecovery` event → `auth.updateUser(password:)` | **link** | **Reset Password** | `{{ .ConfirmationURL }}` |
| Password reset — confirm (browser) | admin panel `/reset-password` | `auth.verifyOtp({token_hash, type: 'recovery'})` (or `setSession` from an `#access_token` fragment) then `auth.updateUser({password})` | **link** | **Reset Password** | `{{ .ConfirmationURL }}` |
| Change sign-in email | Profile → email → `ProfileProvider.updateEmail` | `auth.updateUser(email:)` | **link** | **Change Email Address** (plus **Confirm Email Change** while *Secure email change* is on) | `{{ .ConfirmationURL }}` (the default) |
| Session restore / refresh | automatic (`supabase_flutter` secure storage) | `POST /token?grant_type=refresh_token` | — | — | — |
| Biometric unlock | lock screen | re-uses the persisted session, refreshes it if expired | — | — | — |
| Sign-out | anywhere | `auth.signOut()` | — | — | — |
| Admin panel sign-in | `https://cradi-mobile-admin-production.up.railway.app/login` | `auth.signInWithPassword` | — | — | — |
| Phone / SMS OTP | **disabled in code** (`AuthProvider.phoneAuthEnabled = false`) | — | — | — | — |

Everything the **mobile app** does is code-based **except** the link in the
recovery mail, which the app now handles too (see below). The email change is
the one remaining flow whose link is built from the Site URL — which is why the
Site URL is still not cosmetic.

**Where a recovery link lands.** `resetPasswordForEmail` used to be called
without `redirectTo`, so GoTrue built the link from the **Site URL** — the
admin panel. App users who tapped it were shown a staff login screen they have
no account for. `AuthProvider.sendPasswordResetEmail` now passes
`redirectTo: cradi://reset-password` (`kPasswordResetRedirect`), so:

* reset requested **in the app** → the link opens the app, `supabase_flutter`
  establishes the recovery session, and the router parks on the reset screen
  with only the new-password fields (`/reset-password?recovery=1`);
* reset sent from the **Supabase dashboard** (staff) → no `redirectTo`, so the
  link still resolves to the Site URL and the admin panel's `/reset-password`
  page handles it, exactly as before;
* the mail read on a **desktop** when the app requested it → `cradi://` will not
  open, which is why the **code** stays in the template. Typing it in the app
  is the fallback, and it always works.

This is why the template below uses `{{ .ConfirmationURL }}` rather than a
hand-built `{{ .SiteURL }}/reset-password?token_hash=…`: the hand-built link
ignores `redirectTo` and always points at the admin panel.

The admin panel keeps
`detectSessionInUrl: false` on its shared Supabase client (turning it on would
make every admin page try to consume tokens from its URL); its
`/reset-password` page instead reads `token_hash` — or an `#access_token`
fragment — out of the URL itself and hands it to a short-lived client of its
own. No OAuth provider is involved anywhere.

### a. URL Configuration — **Authentication → URL Configuration**

* **Site URL**: `https://cradi-mobile-admin-production.up.railway.app`
  The default `http://localhost:3000` is what makes a password-reset mail point
  at a dead address. GoTrue applies an email change *server-side* when the link
  is opened and only then redirects the browser here, so the admin login page is
  a fine landing spot even though it ignores the URL fragment.
* **Redirect URLs** (allow list) — GoTrue will only redirect a browser to a URL
  on this list. Add all of these:
  * `https://cradi-mobile-admin-production.up.railway.app/reset-password`
    — **required**. This is where the link in the recovery mail lands (section
    *d*). Without it GoTrue refuses the redirect and the staff-facing half of
    password recovery does not work.
  * `https://cradi-mobile-admin-production.up.railway.app/**`
  * `https://cradi.ng/**` (the app-link host in `AndroidManifest.xml` / `Info.plist`)
  * `cradi://**` (the custom scheme the app registers)

### b. Providers — **Authentication → Providers**

* **Email**: *Enabled*.
  * **Confirm email: ON.** Required, not optional: the admin panel and the
    `profiles_guard` trigger refuse to approve an account whose email (or phone)
    is unconfirmed, so with confirmations off nobody could ever be approved.
  * **Secure email change**: leave ON. The user then gets a confirmation link at
    *both* the old and the new address and must open both.
  * **Email OTP length: 6**, **Email OTP expiry: 3600 s**. The reset screen
    rejects anything shorter than 6 characters and accepts up to 10, so a
    longer OTP length set in the dashboard still works — but the wording in
    the app and in the template below says "code", not "6-digit code", for
    exactly that reason. Keep the two in step if you change it.
* **Phone**: *Disabled*. `AuthProvider.phoneAuthEnabled` is `false`, and the
  login and registration screens hide every phone control behind it. Enabling
  the provider in the dashboard alone changes nothing — the constant has to be
  flipped and the app rebuilt.

### c. Sign-ups — **Authentication → Sign In / Providers**

* **Allow new users to sign up: ON.** The registration screen calls `signUp`;
  with sign-ups disabled Supabase answers `signup_disabled` and the app shows
  "Registration is currently disabled".
* **Allow anonymous sign-ins: OFF** (unused).

### d. Email templates — **Authentication → Emails → Templates**

Two templates must be changed from their shipped, link-based defaults. Paste
these as-is.

**Confirm signup** — subject `Your CRADI verification code`

```html
<h2>Confirm your CRADI / EWER account</h2>
<p>Enter this code in the app to finish creating your account:</p>
<p style="font-size:28px;font-weight:700;letter-spacing:6px;margin:24px 0">{{ .Token }}</p>
<p>The code expires in one hour. If you did not create an account, ignore this email.</p>
```

**Reset Password** — subject `Your CRADI password reset code`

This one template serves **both** audiences and must keep both halves:

* the **code** (`{{ .Token }}`) — for **mobile app users**, and the fallback
  whenever the link cannot open the app (mail read on a desktop, a mail client
  that strips custom schemes). The app's "Create New Password" screen accepts
  it and calls `auth.verifyOTP(type: recovery)`. **Deleting the `{{ .Token }}`
  half leaves anyone in that position with no way to reset at all.**
* the **link** (`{{ .ConfirmationURL }}`) — which now goes wherever the reset
  was *requested from*. Requested in the app, it opens the app; sent from the
  Supabase dashboard, it lands on the admin panel's `/reset-password` page.
  Both destinations must be on the Redirect URL allow list in section *a*
  (`cradi://**` and the admin `/reset-password`), and both already are.

> **Do not** replace it with `{{ .SiteURL }}/reset-password?token_hash={{ .TokenHash }}`.
> A hand-built link ignores `redirectTo` and always points at the admin panel —
> that is precisely the bug this template change fixes.

```html
<h2>Reset your CRADI / EWER password</h2>

<p><strong>Enter this code</strong> on the "Create New Password" screen in the
CRADI app:</p>
<p style="font-size:28px;font-weight:700;letter-spacing:6px;margin:24px 0">{{ .Token }}</p>

<p>Or, if you are reading this on the phone the app is installed on,
<a href="{{ .ConfirmationURL }}">tap here to set a new password</a>.</p>

<p>The code and the link are two forms of the same one-hour, single-use token —
use whichever suits you. If you did not ask for a password reset, ignore this
email — your password has not changed.</p>
```

`{{ .Token }}` is the OTP the app's reset screen asks for; `{{ .ConfirmationURL }}`
is GoTrue's own verify link, which honours the `redirectTo` the request carried
and falls back to the Site URL when it carried none.

**Change Email Address** and **Confirm Email Change**: leave the defaults
(`{{ .ConfirmationURL }}`). This is the only flow that needs a working link, so
it is also the only one that depends on the Site URL above.

**Magic Link**, **Invite user**, **Reauthentication**: unused. The app never
sends a magic link or an invite. `reauthentication_needed` is mapped to a
message in `ProfileProvider.updateEmail`, but no screen collects a reauth code.

> After editing a template, send yourself a real reset **from the app** and read
> the mail on the phone. It must contain **both** a numeric code and a link;
> tapping the link must open the CRADI app on "Create New Password", not a
> browser. Then send one from **Supabase → Users → Send password recovery** and
> check that its link opens the admin panel's `/reset-password`. Both have to
> work — they are the two audiences this one template serves.

### e. SMTP — **Project Settings → Authentication → SMTP Settings**

* Custom SMTP **enabled**, pointed at Resend. The sender domain must be verified
  in Resend or every message is silently dropped.
* **Sender email / name** must match a verified Resend identity.

### f. Rate limits — **Authentication → Rate Limits**

* **Emails sent per hour**: the default is `2` while the built-in SMTP is in
  use. With custom SMTP raise it to at least `30`, otherwise a user who
  registers, mistypes the code and asks for a resend hits
  `over_email_send_rate_limit` and the app says "Too many attempts".
* **Token verifications** and **sign-ins**: the defaults are fine.

### g. What the code additionally assumes

* The `on_auth_user_created` trigger reads the `raw_user_meta_data` keys `name`,
  `role`, `phone`, `state`, `lga`, `ward`, `address` and creates the `profiles`
  row. The client never inserts it, so a failure here leaves a user who can sign
  in but has no profile.
* A requested `role` outside the six self-service values is silently demoted to
  `user`, and `is_approved` always starts `false` — every new account lands on
  `/pending-approval` until an admin approves it.
* The app subscribes to its own `profiles` row over Realtime, so **Realtime must
  be enabled for `public.profiles`**: that is what makes an approval, a role
  change or a disable take effect without a restart.
* The admin panel has a password-reset screen at `/reset-password` (public, not
  behind the admin sign-in guard). An admin who forgets their password asks for
  a recovery mail — from the mobile app's `/forgot-password`, or from Supabase →
  Authentication → Users → *Send password recovery* — and follows the link in
  it. It works for any account, not only admins: the page uses its own
  short-lived Supabase client, so the admin-only guard never sees the recovery
  session. After the change it signs the account out everywhere, so the next
  sign-in uses the new password.
* The panel enforces the same password rules as the app
  (`admin/lib/password.ts` mirrors `lib/core/utils/password_validator.dart`):
  8–128 characters, upper and lower case, a digit, a special character, not a
  common password, no sequential run such as `123` or `abc`. Supabase's own
  *Minimum password length* / *Required characters* setting applies on top and
  its message is shown verbatim.
* Login throttling is **per device**, in the app's own `RateLimiter` (5 attempts
  / 15 min, then an exponentially growing lock). It is independent of Supabase's
  limits and clears itself when the lock expires or on the next successful
  sign-in.

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
   `https://cradi-backend.up.railway.app`. You need it to check `/health` and
   to reach `POST /email`; the Flutter app does not call the backend directly
   (it talks to Supabase, and the backend reacts to what the database queues),
   so no build-time value is needed for it.
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
| `SENTRY_DSN` | no | Sentry DSN | crash reporting disabled |
| `APPWRITE_IMAGE_TRANSFORMS` | no | `true` | smaller renders are not requested; the full-size image is used |

#### `APPWRITE_IMAGE_TRANSFORMS` (optional smaller renders)

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

Anything that is not one of this backend's own file URLs — admin-set
knowledge-base images on other hosts, `data:` URIs, local file paths —
is left exactly as it is.

`AppConfig` also holds non-configurable constants (the Android
`applicationId`, the Play Store URL, table names and the two storage bucket
names) — nothing to set there.

### Using `env.json`

```bash
cp env.example.json env.json     # env.json is git-ignored
# edit env.json: SUPABASE_URL, SUPABASE_ANON_KEY, ONESIGNAL_APP_ID, SENTRY_DSN,
#                APPWRITE_IMAGE_TRANSFORMS (optional)
flutter pub get
flutter run   --dart-define-from-file=env.json
flutter build apk --release --no-tree-shake-icons --dart-define-from-file=env.json
```

`env.example.json` is the template and contains only placeholders. The CI
release job writes `env.json` from the repository secrets `SUPABASE_URL`,
`SUPABASE_ANON_KEY`, `ONESIGNAL_APP_ID` and `SENTRY_DSN`
(`APPWRITE_IMAGE_TRANSFORMS` is left unset unless the secret is set).
Signing: see `docs/KEYSTORE_SETUP.md`.

> **The OneSignal REST API key must never be passed to the app** — not in
> `env.json`, not as a `--dart-define`, not in `AppConfig`, not obfuscated.

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
against the sandbox and **every push silently fails**.

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
deliberately rather than answered `false`:

* `lib/core/services/hive_encryption_service.dart` opens the local Hive boxes
  with an AES-256 cipher (key generated in-app, stored in the Keychain).
* `lib/core/services/encryption_service.dart` implements AES-256-GCM with
  PBKDF2-SHA256 (PointyCastle).

The algorithms are standard, but they are **not** limited to HTTPS/TLS, the
platform's own crypto, or authentication — the categories the usual "exempt"
answers cover. Whoever owns export compliance should decide between declaring
`false` and declaring the app 5D992.c mass market (which carries an annual
self-classification report to BIS), then add the key.

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
`app_settings` table. When the build is older, `ForceUpdateGate`
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

iOS has no App Store id yet, so the gate hides its "Update" button there
(`AppConfig`); an iOS user sees the blocking screen with no way to act. Do not
raise `app_min_version` once an iOS build is in users' hands until
`AppConfig` carries an App Store link.

#### Release checklist

- [ ] `version:` bumped in `pubspec.yaml` (build number always increases)
- [ ] `CHANGELOG.md` updated
- [ ] Tag pushed as `v<version>` — the `build-android-release` CI job only
      runs for `refs/tags/v*` and needs the signing secrets from
      `docs/KEYSTORE_SETUP.md`
- [ ] APK/AAB uploaded and rollout live on Play
- [ ] `app_min_version` raised **only if** this release is mandatory


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
4. **Deep links.** `lib/core/services/deep_link_service.dart` listens for
   `cradi://…` and `https://cradi.ng/…` with `app_links` and hands the mapped
   location to `go_router`; Supabase auth callbacks are filtered out and left
   to `supabase_flutter`. The mapping is unit-tested
   (`test/unit/deep_link_service_test.dart`) but has never run on a device.
   The Android manifest sets `android:autoVerify="true"` for `https://cradi.ng`,
   which needs `https://cradi.ng/.well-known/assetlinks.json` published with the
   **release** signing certificate's SHA-256; on iOS, Universal Links need the
   *Associated Domains* entitlement (`applinks:cradi.ng`) and an
   `apple-app-site-association` file. Without those, `https://` links open a
   browser/chooser instead of the app — the `cradi://` scheme works regardless.

One ProGuard leftover, listed so nobody reads it as protection: the
`com.google.gson.**` keep rule matches no Java class in this app. The
`okhttp3.**` rules do apply — OkHttp arrives transitively with Sentry and
OneSignal.

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
and a Nigerian phone number you control. Both are picked together from the
list, which is grouped by state: the state is required, and a contact is texted
only for its own state's LGA (`20260927090000`).

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
   **target state = X** and **target LGA = Y**. The state comes first and is
   required: six LGA names (Bassa, Ifelodun, Irepodun, Nasarawa, Obi,
   Surulere) belong to two states each, so an LGA on its own names no single
   place. The database enforces it — `alerts` has a check constraint
   (`alerts_target_lga_needs_state`) plus foreign keys into
   `public.nigeria_states` / `public.nigeria_lgas`, so an alert with an LGA and
   no state, an invented state, or an LGA that is not in the state it claims,
   is rejected at insert time. The three targetings that remain are: one LGA of
   one state; every LGA of one state (`All` + a state); and everyone
   (`All`, no state).
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

Every authority names the state of the LGA it covers, and is texted for that
(state, LGA) only. Migration `20260927090000` made `coverage_state` NOT NULL
and added foreign keys into `public.nigeria_states` / `public.nigeria_lgas`, so
a contact with no state, an invented state, or an LGA that is not in the state
it claims, is rejected at insert time. Six LGA names (Bassa, Ifelodun,
Irepodun, Nasarawa, Obi, Surulere) exist in two states each: before that
migration a state-less contact for one of them was texted about incidents in
both.

A report whose `state` is empty therefore matches **no** authority and sends no
SMS, logged as `sms.report_without_state`. That is deliberate — texting the
wrong state's emergency desk is worse than texting no one — so fix the report's
`state` rather than the query.

**If that migration quarantined contacts** it raised a `WARNING` naming each
one, and copied them into `public.authorities_unresolved_coverage` (service
role only). Those numbers are **no longer being texted**. Recover them:

```sql
-- SQL editor (service role)
select id, name, organization, phone, coverage_lga, coverage_state, reason
  from public.authorities_unresolved_coverage
 order by quarantined_at;
```

For each row, establish which state that desk actually serves — ask them if you
have to, never guess — re-add it under **Admin → Authorities** (the LGA list is
grouped by state), then `delete` the row from the quarantine table. It holds
real names and phone numbers, so do not leave it populated.

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
