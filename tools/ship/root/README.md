# EWER — Early Warning Early Response

Two applications over one Appwrite backend.

| | |
|---|---|
| **`mobile/`** | The Flutter app the public and the field authorities use. Also holds the Appwrite Functions every client write goes through (`mobile/functions/cradi`), the deployment toolchain (`mobile/infra/appwrite`) and the Supabase → Appwrite migration pipeline. |
| **`web/`** | The Next.js admin panel, deployed to Appwrite Sites. |

They were separate repositories and keep their own directories, so each
still builds, tests and deploys on its own. Nothing is shared at the root
but the CI workflows and these documents.

## Start here

- **[`docs/IMPLEMENTATION.md`](docs/IMPLEMENTATION.md)** — how the system fits
  together: the backend, what each app is responsible for, where
  configuration comes from, and how a change reaches production.
- **`mobile/docs/DEPLOYMENT.md`** — releasing the Android app.
- **`mobile/docs/CUTOVER-RUNBOOK.md`** — the migration and cutover procedure,
  including deploying the Functions, which nothing in CI does.
- **`web/SETUP.md`** — running and deploying the admin panel.

## Quick start

```bash
# The mobile app. env.json is not in the repository; see IMPLEMENTATION.md.
cd mobile
flutter pub get
flutter run --dart-define-from-file=env.json

# The admin panel. .env.local is not in the repository either.
cd web
npm ci
npm run dev
```

## CI

`.github/workflows/mobile.yml` and `.github/workflows/web.yml`. Each is the
workflow that app had as its own repository, re-rooted under its directory:
every job carries a `defaults.run.working-directory`, and the action inputs
that `working-directory` does not reach — `cache-dependency-path`,
`upload-artifact`'s `path`, codecov's `file` — are prefixed separately.

Between them they run the Flutter analyzer and test suite, a debug APK
build, a signed release APK build on a `v*` tag, four Node suites including
the migration pipeline against a real Postgres 16, a backend Docker build,
and the admin panel's typecheck, lint, production build and Playwright
end-to-end suite.

## What is deliberately not here

`env.json`, `web/.env.local`, `android/key.properties` and the signing
keystore. They carry credentials and are produced per machine; see
`docs/IMPLEMENTATION.md` for what each needs and where the values live.
