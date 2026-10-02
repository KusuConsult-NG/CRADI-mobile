# A real Appwrite, locally

Appwrite 1.8.0 on ports **8090** (API) and **8091** (realtime), beside
the 1.6.2 spike — which still holds the Phase 0–6 proofs and keeps 8080.

```
docker network create runtimes18
docker compose -f infra/appwrite/local/docker-compose.yml up -d
echo "127.0.0.1 appwrite.local" | sudo tee -a /etc/hosts     # see below
node infra/appwrite/local/bootstrap.mjs
source infra/appwrite/local/.env.local
node infra/appwrite/provision.mjs
node infra/appwrite/local/deploy.mjs
```

Then the three end-to-end suites:

```
node infra/appwrite/local/e2e.mjs             # a hazard report, filed to delivered
node infra/appwrite/local/e2e-auth.mjs        # typed codes, recovery, enumeration
node infra/appwrite/local/e2e-escalation.mjs  # the cron, firing on its own
```

and the Dart adapters:

```
eval "$(node infra/appwrite/local/prep-dart.mjs)"
flutter test \
  --dart-define=APPWRITE_ENDPOINT="$APPWRITE_ENDPOINT" \
  --dart-define=APPWRITE_PROJECT_ID="$APPWRITE_PROJECT_ID" \
  --dart-define=DART_TEST_SESSION="$DART_TEST_SESSION" \
  --dart-define=DART_TEST_EMAIL="$DART_TEST_EMAIL" \
  --dart-define=DART_TEST_PASSWORD="$DART_TEST_PASSWORD" \
  --dart-define=DART_TEST_USER_ID="$DART_TEST_USER_ID" \
  test/integration
```

Without those defines the integration tests **skip**, so `flutter test`
stays green in CI.

## Why `appwrite.local` and /etc/hosts

Appwrite routes by `Host`. A request whose Host is not the configured
`_APP_DOMAIN` is answered by the **console**, which returns a page of
HTML with a 200 — and a client reads that as "not found" rather than as
a misroute. So one name has to work from both sides:

- inside the compose network, a Function reaches
  `http://appwrite.local/v1` through a network alias;
- from this machine, `/etc/hosts` points `appwrite.local` at the
  published port.

The name is **dotted** on purpose. The session cookie is issued for
`domain=.<_APP_DOMAIN>`, and a single-label domain like `.appwrite` is
not a valid cookie domain.

The /etc/hosts line is not optional and does not survive a container
rebuild. If calls start returning HTML, check it first.

## Known gap: `signInWithPassword` on an IO client

`AppwriteAuthBackend.signInWithPassword` relies on the Flutter SDK's
cookie jar. Against this stack the session is created — Appwrite returns
201 with three `Set-Cookie` headers — and the **next call is a guest**.
It is not a timing race (a 250 ms wait does not help), and the fallback
header Appwrite exposes for exactly this case is browser-only in the
SDK.

So the Dart integration tests authenticate with `Client.setSession` and
a server-minted secret, which is the same mechanism
`AppwriteAuthBackend._establish` uses after a typed code is redeemed —
the path sign-up and recovery actually take.

**This must be verified on Cloud before launch.** Plain HTTP, the
`.local` suffix and the local cookie attributes are all candidates, and
every Appwrite Flutter app in the world signs in this way over HTTPS, so
it very likely works there. "Very likely" is not a test.
