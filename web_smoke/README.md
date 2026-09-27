# `web_smoke/` — browser smoke-test harness (TEST ONLY)

A throwaway rig that runs the **real** Flutter app in Chromium against a
**local in-memory mock** of Supabase, walks every screen, screenshots each one
and records console errors, uncaught exceptions and failed requests.

> Nothing in here ships. It never contacts a real Supabase project: the app is
> built with `SUPABASE_URL=http://127.0.0.1:54321`, which is this mock.

Web is **not** the shipped platform. Plugin-backed features (OneSignal push,
`local_auth` biometrics, `geolocator`, `flutter_tts`, camera `image_picker`,
Hive encryption, `dart:io` file handling) degrade or throw in a browser. Treat
those as environment noise, not as app defects, unless the failure is in the
app's own Dart code.

## Parts

| File | What it is |
| --- | --- |
| `mock-supabase.mjs` | In-memory GoTrue + PostgREST + Realtime + Storage mock on `127.0.0.1:54321`, seeded with every role, all 9 hazard categories, alerts, guides, contacts, chat, news links and app settings. Adapted from `CRADI-Mobile-Admin/e2e/mock-supabase.mjs`. |
| `serve.mjs` | Static server for `build/web` (with the right `application/wasm` type). |
| `driver.mjs` | Playwright helpers. Flutter paints to a canvas, so the driver turns on Flutter's accessibility tree and drives the app through `<flt-semantics>` nodes. |
| `smoke.mjs` | The tour: signed-out screens, one pass per role, the report wizard, a language pass over all 5 locales and a 320×640 pass. |
| `run.sh` | Builds, starts both servers, runs the tour, tears everything down. |

## Running it

```bash
./web_smoke/run.sh              # everything
./web_smoke/run.sh roles        # only the per-role passes
```

Pass names:

| Pass | What it walks |
| --- | --- |
| `signed-out` | splash, onboarding, landing, login (incl. validation and bad credentials), forgot/reset password, registration, OTP, help, 404 |
| `roles` | one full tour per role — `role-user`, `role-ewm`, `role-ewv`, `role-ewr`, `role-admin` — through every screen the shell can reach, plus the report wizard. The admin tour also opens the per-row overflow menus on the admin users and knowledge screens, whose icons only exist while the menu is open. |
| `edge` | the pending-approval and unverified accounts, and the routes they are bounced from |
| `offline` | every offline-allowed screen with the browser offline, then back online |
| `wizard` | the report wizard across five hazard categories |
| `focus` | the interactions the broad tour cannot reach cleanly: settings toggles, peer verification vote, report view with peer votes, the severity slider, search fields |
| `languages` | English, then Hausa, Yoruba, Igbo and Pidgin across 16 screens each, comparing every label against the English baseline |
| `small` | the whole tour at 320×640 |

Two quirks the driver works around, both from Flutter's semantics tree and
neither an app defect:

* a widget below the fold must be scrolled into view before it is clicked —
  its rect is outside the viewport but not clipped;
* a `Slider` is published as `<input type=range>`, but the engine never reads
  that element's value as a position — each `change` becomes one `increase` /
  `decrease` action, so `setRange()` dispatches one change per step instead
  of assigning the target value once.

The navigation Drawer is a route overlay that neither Escape nor a URL change
closes, so it is always opened as the last step of a pass.

Outputs:

* `web_smoke/screenshots/<pass>/NNN-<screen>.png`
* `web_smoke/highlights/NN-<screen>.png` — a hand-picked set copied out of the
  passes above, to look at without reading the whole report
* `web_smoke/report.json` — per-screen record plus every console/page error
* `web_smoke/language-texts.json` — every visible label per screen per language

## Seeded accounts

All use the password `Password123!`.

| Email | Role / state |
| --- | --- |
| `user@cradi.test` | plain `user` |
| `ewm@cradi.test` | `ewm` (monitor) |
| `ewv@cradi.test` | `ewv` (validator) |
| `ewr@cradi.test` | `ewr` (responder) |
| `ldp@cradi.test` | `ldp_coordinator` |
| `staff@cradi.test` | `project_staff` |
| `admin@cradi.test` | `admin` |
| `tech@cradi.test` | `techSupport` |
| `pending@cradi.test` | approved = false → `/pending-approval` |
| `unverified@cradi.test` | email unconfirmed → `/verify-access-code` |
| `disabled@cradi.test` | `is_disabled` |

Every OTP the mock issues (sign-up confirmation, password recovery) is
`123456`.

## Environment notes

* The container's default locale is `en-US@posix`, which `Intl` rejects and
  which crashes the Flutter engine before the first frame. The harness pins the
  browser locale to `en-US`.
* `fonts.gstatic.com` is unreachable, so `google_fonts` (Outfit) cannot load.
  The harness serves a local Liberation Sans for every Google Fonts request.
* Build with `--no-web-resources-cdn` so CanvasKit is served locally.
