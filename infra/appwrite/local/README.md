# A real Appwrite, locally

Appwrite 1.9.6 on ports **8090** (API) and **8091** (realtime).

Pinned to 1.9.6, not the 1.8.0 this started on and not the 2.3 the
Flutter SDK targets. See [Which server version](#which-server-version).

```
./infra/appwrite/local/up.sh          # network, /etc/hosts, compose, wait
node infra/appwrite/local/bootstrap.mjs
source infra/appwrite/local/.env.local
node infra/appwrite/provision.mjs
node infra/appwrite/local/deploy.mjs
```

Then the end-to-end suites:

```
node infra/appwrite/local/e2e.mjs             # a hazard report, filed to delivered
node infra/appwrite/local/e2e-auth.mjs        # typed codes, recovery, enumeration
node infra/appwrite/local/e2e-escalation.mjs  # the cron, firing on its own
node infra/appwrite/local/e2e-operation.mjs   # reopen_report, and who may run it
node infra/appwrite/local/e2e-sms.mjs         # authority SMS, against a stand-in Termii
node infra/appwrite/cloud-check.mjs           # the behaviour a Cloud run must also show
```

`e2e-sms.mjs` starts its own HTTP server and points `TERMII_BASE_URL` at
it, so the whole send path runs — the numbers, the text, both caps, the
deterministic claim and the bookkeeping — without texting anyone. What
it cannot prove is Termii's own API contract.

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

Pass them to `test/integration` and not to the whole tree. Several unit
tests assert what the app does when **no** backend is configured, and
`--dart-define=APPWRITE_ENDPOINT=…` is exactly the thing that makes it
configured — so `flutter test <defines> test` fails nine of them for a
reason that has nothing to do with the code under test. (Pre-existing;
noted here because it reads like a regression and is not one.)

## Which server version

The Flutter SDK (27.x) targets Appwrite **2.3**, which is what Cloud
runs. Self-hosted lags, and the gap is not cosmetic:

| | 1.8.0 | 1.9.6 | 2.3.0 |
|---|---|---|---|
| realtime: channels in a `subscribe` frame | ✗ | ✓ | ✓ |
| execution carries `resourceId`/`resourceType` | ✗ | ✗ | ✓ |
| deployments need the `orchestrator` image | – | – | ✓ |

1.8 closes the websocket with `1008 Missing channels` because the SDK
sends `project` alone and the channels afterwards. 1.9.6 speaks that
protocol, which is why the stack moved.

Neither 1.8 nor 1.9 returns the execution shape the SDK parses, so
`DataBackend.callOperation` throws `Bad state: No element` before the
response body is read — in the SDK's model, not in our code. The two
Dart tests for it are **skipped** with that reason; the Function itself
is covered by `e2e-operation.mjs` over HTTP.

2.3 self-hosted would close that last gap, but from 2.0 a deployment is
built through `ghcr.io/open-runtimes/orchestrator`, and this
environment's network policy refuses `pkg-containers.githubusercontent.com`,
so no Function can be deployed there. The adapter's `callOperation`
therefore stays **unverified until it runs against Cloud** — alongside
the cookie-session gap in `signInWithPassword` (Phase 16).

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
