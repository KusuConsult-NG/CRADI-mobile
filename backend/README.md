# CRADI / EWER backend (Railway)

Small Node 22 service that replaces the old Firebase Cloud Functions (and the
legacy Appwrite functions). It runs next to Supabase (database, auth, storage)
and sends push notifications through OneSignal, email through Resend and SMS
to local authorities through Termii or Twilio.

It does three things:

| Part | What it does |
| --- | --- |
| **Outbox worker** | Polls `notification_outbox` (filled by database triggers) and sends pushes: verification requests, reporter status updates, approved-report broadcasts (+ SMS to local authorities), dispute escalations, admin alerts. |
| **Escalation cron** | Every minute, reports still `pending` past `scheduled_escalations.escalate_at` are flagged as escalated and coordinators/staff are notified. |
| **HTTP API** | `GET /health` and `POST /email` (authenticated transactional email). |

Runtime dependency: `@supabase/supabase-js` only. OneSignal, Resend, Termii and Twilio are called with `fetch`.

## Layout

```
src/
  index.js          wiring, loops, graceful shutdown
  config.js         env parsing
  server.js         node:http server (health, /email, CORS)
  outbox.js         outbox handlers + dispatch
  escalations.js    escalation cron
  notifications.js  pure recipient-selection + message builders
  onesignal.js      OneSignal REST client
  repo.js           all Supabase queries
  tags.js           OneSignal tag sanitisation (shared contract)
  sms/              phone normalisation, Termii/Twilio clients, authority SMS (caps, dedupe)
  email/            templates + /email handler (auth, anti-abuse, rate limits)
test/               node:test suites (no network)
```

## Environment variables

| Variable | Required | Default | Notes |
| --- | --- | --- | --- |
| `SUPABASE_URL` | yes | | `https://<ref>.supabase.co` |
| `SUPABASE_SERVICE_ROLE_KEY` | yes | | Service role key (bypasses RLS). Keep it only on Railway. |
| `ONESIGNAL_APP_ID` | for push | | If unset, pushes are logged and skipped. |
| `ONESIGNAL_REST_API_KEY` | for push | | App API key, sent as `Authorization: Key <key>`. |
| `ONESIGNAL_ANDROID_CHANNEL_ID` | no | | Optional Android notification category id. |
| `RESEND_API_KEY` | for email | | If unset, `POST /email` returns 503. |
| `FROM_EMAIL` | no | `noreply@cradi.ng` | Must be on a domain verified in Resend. |
| `FROM_NAME` | no | `EWER Alert System` | |
| `SMS_PROVIDER` | for SMS | | `termii` or `twilio`. Unset/unknown or incomplete credentials: authority SMS are logged and skipped. |
| `TERMII_API_KEY` | termii | | Termii API key. |
| `SMS_SENDER_ID` | termii | | Registered Termii sender ID (the `from`). |
| `TWILIO_ACCOUNT_SID` | twilio | | Basic-auth user. |
| `TWILIO_AUTH_TOKEN` | twilio | | Basic-auth password. |
| `TWILIO_FROM` | twilio | | Sending number (E.164) or messaging-capable sender. |
| `PORT` | no | `8080` | Railway sets this. |
| `WORKER_POLL_MS` | no | `5000` | Outbox poll interval (a full batch of 50 re-polls immediately). |
| `ESCALATION_POLL_MS` | no | `60000` | Escalation check interval. |
| `CORS_ORIGINS` | no | empty | Comma-separated browser origins for `/email`, or `*`. The mobile app needs none. |

If a required variable is missing the service logs `config.missing_required`,
does not start the worker or cron, and `/health` returns **503**, so a Railway
deploy with a bad config fails its health check.

## Run locally

```bash
cd backend
cp .env.example .env      # fill in values
npm install
npm run dev               # node --watch, loads .env
npm test                  # node:test, no network needed
curl localhost:8080/health
```

## Deploy on Railway

1. Railway: **New Project → Deploy from GitHub repo**, pick this repository.
2. Service **Settings → Source → Root Directory = `backend`**. Railway then
   uses `backend/railway.json` (Dockerfile build, `node src/index.js`,
   health check `/health`, restart on failure).
3. Service **Variables**: add the variables above (at least the two Supabase ones).
4. **Settings → Networking → Generate Domain** to get a public URL for `/email`
   (e.g. `https://cradi-backend.up.railway.app`). Put that URL in the Flutter app config.
5. Several replicas are safe: outbox rows are claimed with `FOR UPDATE SKIP LOCKED`,
   escalations use conditional updates, and every push has an idempotency key.
   One replica is enough.

## OneSignal setup

1. Create a OneSignal app; configure Android (FCM v1 service-account JSON
   **inside OneSignal only**; the app itself no longer uses Firebase) and iOS (APNs `.p8` key).
2. **Settings → Keys & IDs**: copy the App ID and create an App API key →
   `ONESIGNAL_APP_ID`, `ONESIGNAL_REST_API_KEY`.
3. Optional: create an Android notification category (e.g. "Alerts", high
   importance) and set `ONESIGNAL_ANDROID_CHANNEL_ID` to its id.

### Contract with the Flutter app

- **External ID**: after sign-in the app calls `OneSignal.login(<supabase user uuid>)`.
  Direct pushes target `include_aliases.external_id = [uuid]`.
- **Tags**: the app sets `role`, `lga`, `state`, `ward`, `monitoring_zone` from
  the user's profile. Every value is sanitised with the same rule used here
  (`src/tags.js`):

  ```
  value.toLowerCase().replace(/[^a-z0-9_]/g, '_')
  ```

  No trimming and no collapsing of repeated `_`. Examples:
  `"Port Harcourt" → "port_harcourt"`, `"Obio/Akpor" → "obio_akpor"`.
  Dart equivalent: `value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '_')`.
- Approved-report broadcasts and LGA-targeted admin alerts use the filter
  `tag lga = sanitize(report.lga / alert.target_lga)`. Alerts with
  `target_lga = 'All'` go to the `Total Subscriptions` segment.
- Push `data` payloads (use `type` to route taps in the app):

  | type | fields |
  | --- | --- |
  | `verification_request` | `report_id` |
  | `report_status` | `report_id`, `status` |
  | `validated_alert` | `report_id` |
  | `admin_alert` | `alert_id`, `severity` |
  | `escalation_auto` | `report_id` |
  | `escalation` | `report_id` (report disputed by a peer) |

### Push privacy and Identity Verification

Without OneSignal **Identity Verification**, any device can call
`OneSignal.login(<someone else's uuid>)` or set any `lga` tag and receive that
user's / area's pushes. Push titles, bodies and `data` are therefore generic:
they carry only the event `type` and ids (`report_id` / `alert_id`, plus the
report `status` enum) — never ward / LGA names, hazard free text, report
descriptions or rejection reasons. The app loads the details after sign-in,
through RLS. Admin alerts (`alert_created`) are intentionally public
broadcasts: their title/message are sent, but whitespace-normalised and capped
(80 / 240 characters).

**Production:** enable Identity Verification in the OneSignal dashboard
(Settings → Keys & IDs → Identity Verification). **Follow-up required:** once
enabled, the app must pass a server-issued JWT for the external id on
`OneSignal.login` (a small endpoint here, signed with the OneSignal identity
key, would issue it for the caller's Supabase session). Until then, keep push
content generic as above.

## Resend setup

1. Add and verify the sending domain (e.g. `cradi.ng`) in Resend (SPF/DKIM DNS records).
2. Create an API key with "sending access" → `RESEND_API_KEY`.
3. `FROM_EMAIL` must be an address on the verified domain.

Supabase Auth sends its own emails (confirmation, OTP, password recovery).
Configure custom SMTP in Supabase (Resend offers SMTP) for those; this service
does not send `verification` or `passwordReset` emails.

## How the outbox works

Database triggers (see `supabase/migrations/*_init.sql`) insert rows into
`notification_outbox`:

| event_type | payload | inserted when |
| --- | --- | --- |
| `report_created` | `{report_id}` | new report with status `pending` |
| `report_status_changed` | `{report_id, old_status, new_status, reason}` | `reports.status` changes |
| `alert_created` | `{alert_id}` | new active alert |
| `user_access_changed` | `{user_id}` | `profiles.is_disabled` changed (block/unblock from web, mobile or SQL) |
| `report_disputed` | `{report_id, verification_id}` | a peer inserts a verification with `is_confirmed = false` on a pending report (trigger to be added in a migration) |

The worker calls `rpc('claim_outbox_events', {p_limit: 50})`. That function
atomically bumps `attempts` and moves `available_at` into the future
(exponential backoff up to 60 min, max 8 attempts), so a crashed worker's
events come back later on their own. For each event:

- success → `processed_at = now()` (with an informational note in `last_error`
  when there was nothing to do, e.g. "report not found");
- failure → `last_error` is set and the row is retried after its backoff;
- unknown `event_type` or invalid payload → marked processed with a note
  (`unknown event`).

Handlers:

- **report_created**: approved, enabled `ewm` profiles in the same ward **and**
  LGA as the report (excluding the reporter, max 50) get "📋 Verification Request"
  ("A report in your area needs verification").
- **report_status_changed**: the reporter gets a status update (verified /
  approved / rejected / pending; the rejection reason is *not* pushed — "open
  the app for details"). On a transition **into** `approved`, users tagged with
  the report's LGA get a generic "🚨 Verified Hazard Alert".
  On that same transition, local authorities are texted (see *Authority SMS*).
- **report_disputed**: if the report is still `pending` and not yet escalated,
  it is escalated (`escalated = true, escalated_at, escalation_reason =
  'Disputed by a peer monitor [event <outbox id>]', escalation_status =
  'escalated'`), its pending
  `scheduled_escalations` row is marked `processed`, and the same recipients as
  the timeout escalation get "⚠️ Disputed Report Escalated" (`type: escalation`).
  Otherwise the event is processed with a note (`report already escalated`,
  `report no longer pending (…)`). A retry after a failed push re-sends the
  (idempotent) push only when `escalation_reason` names *this* event, so a
  second dispute event never re-notifies an escalation made by the first. The escalation cron skips reports already escalated for
  another reason.
- **user_access_changed**: applies (`ban_duration: 876000h`) or lifts (`none`) the Supabase Auth ban to match the profile's current `is_disabled`, so blocking from the mobile admin screen also stops sign-in.
- **alert_created**: title/message of the alert to everyone (`All`) or to the
  LGA tag.

Blocked / deleted users: recipient lookups only select approved profiles with
`is_disabled = false`, and a deleted user's profile (and reports) are gone, so
they are not targeted. There is no user-disable hook in the worker: the
reporter's own status update is still sent to `report.user_id` if that account
was blocked after reporting (the body is generic). Blocking also bans the Auth
account; the device keeps its OneSignal external id until the app signs out
(which calls `OneSignal.logout()`), so a blocked device may still receive LGA /
"All" broadcasts until then — another reason pushes stay generic.

Each OneSignal request carries an `idempotency_key` (a UUID v4-formatted SHA-256
hash of the outbox id or escalation id), so retries never double-notify.

Stuck events: `select * from notification_outbox where processed_at is null and attempts >= 8;`

## Authority SMS

On a transition into `approved` (same rule as the LGA broadcast), rows of
`authorities` with `coverage_lga = report.lga` (exact match, at most
`app_settings.max_sms_per_alert_event`, default 20) get:

```
EWER ALERT: {SEVERITY} {hazard_type} reported in {ward}, {lga}. {description} - verified by community monitors.
```

truncated to 320 characters (the description is shortened with `...`).

- Phone numbers are normalised to E.164 `+234XXXXXXXXXX` (`0803…`, `803…`,
  `234803…`, `+234 (0)803…`, `00234…`); invalid or non-Nigerian numbers are
  skipped and logged; duplicate numbers get one SMS.
- Daily cap: `app_settings.max_sms_per_lga_per_day` (default 50) successful SMS
  per LGA per day (Africa/Lagos day), counted in memory per instance.
- Dedupe: once a report's SMS round completes it is never texted again by this
  instance; if every send fails the event is retried (outbox backoff) and
  numbers that already received the SMS are not texted again.
- Providers (isolated in `src/sms/providers.js`, 15 s timeout):
  - `termii`: `POST https://api.ng.termii.com/api/sms/send`, JSON
    `{api_key, to: "234…", from: SMS_SENDER_ID, sms, type: "plain", channel: "generic"}`;
  - `twilio`: `POST https://api.twilio.com/2010-04-01/Accounts/{SID}/Messages.json`,
    form `To, From, Body`, basic auth `SID:token`.
  - unset: logged (`sms.skipped_not_configured`) and skipped; nothing fails.

The counters and dedupe set are in memory: a restart resets the daily cap and
forgets completed reports (the outbox has already marked those events processed,
so they are not replayed).

## Escalation cron

Every `ESCALATION_POLL_MS` it loads up to 100 `scheduled_escalations` with
`status = 'pending' and escalate_at <= now()`:

- report missing or no longer `pending` → escalation `skipped` with a reason;
- report already escalated for another reason (e.g. a peer dispute) → `skipped`
  (`Already escalated: …`);
- otherwise the report gets `escalated = true, escalated_at, escalation_reason,
  escalation_status = 'escalated'` (its `status` stays `pending`), approved
  enabled `ldp_coordinator`/`ewr` in the report's LGA plus `project_staff`/`ewv`
  anywhere (max 50 each, deduplicated) get "⏰ Unverified Report Escalated", and
  the escalation is marked `processed`;
- if the push fails the escalation stays `pending`, `reason` becomes
  `attempt N: <error>` and `escalate_at` moves forward with exponential backoff
  (1, 2, 4, 8 min, capped at 60), so a failing row cannot starve newer ones;
  after 5 failed attempts it is marked `skipped` (`Gave up after 5 attempts: …`).

Outbound requests (Supabase, OneSignal, Resend, Termii, Twilio) time out after 15 s.

## HTTP API

### `GET /health`

`200 {ok: true, config: {supabase, onesignal, resend, sms}, workers: {...}}`, or
`503` with `ok: false` when required config is missing. Each entry in
`workers` has `lastRunAt`, `lastSuccessAt`, `stale` and `healthy`; a loop is
unhealthy when its last tick failed or it has not completed a tick for more
than 5× its poll interval.

### `POST /email`

```
Authorization: Bearer <Supabase access token>
Content-Type: application/json

{ "type": "welcome" | "hazardAlert" | "reportUpdate",
  "to": "user@example.com",
  "data": { ... } }
```

| type | data |
| --- | --- |
| `welcome` | `name`, `email`, `role?` |
| `hazardAlert` | `hazardType`, `severity`, `location?`, `description`, `lga?`, `ward?`, `state?`, `timestamp?` |
| `reportUpdate` | `reportId`, `status`, `message?`, `reporterName?` |

Responses: `{success: true, messageId}` or `{success: false, error}`
(`400` bad input, `401` bad token, `403` recipient not allowed, `429` rate limited,
`502` provider failure, `503` not configured). Provider error details are only logged.

Anti-abuse rules:

- The token is checked with `supabase.auth.getUser(token)`.
- `to` must be the caller's own email, unless the caller's profile is approved,
  not disabled and has the role `admin`, `ldp_coordinator` or `project_staff`.
  Other roles (including `ewm`, `ewv`, `ewr`, `techSupport`) may only email
  themselves. Disabled accounts are refused.
- One email per recipient per minute, 20 emails per caller per hour
  (in memory, per instance).
- All template values are HTML-escaped.
