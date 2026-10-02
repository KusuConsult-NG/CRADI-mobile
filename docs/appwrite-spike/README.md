# The Appwrite spike

Scripts behind the claims in `../APPWRITE-MIGRATION.md`. They are evidence,
not a deliverable — nothing here ships.

Appwrite Cloud is unreachable from the CI container (the egress proxy refuses
`appwrite.io` and `fra.cloud.appwrite.io` alike), and the published
self-hosted compose lives on that same blocked domain. `docker-compose.yml`
here is the smallest stack that answers the questions: API, databases worker,
realtime, MariaDB, Redis. It is not a deployment.

    docker compose up -d
    docker compose exec appwrite migrate
    node setup.mjs        # project + API key -> env.json

| Script | Answers |
|---|---|
| `spike.mjs` | Phase 0 — ward-scoped reads as document ACLs; 8/8, lists filtered, membership move |
| `realtime.mjs` | Phase 0 — Realtime is filtered by the same ACLs |
| `auth2.mjs` | Phase 2 — Appwrite's own verification/recovery are link-based |
| `auth3.mjs` | Phase 2 — the code-based route, end to end |
| `auth4.mjs` | Phase 2 — session expiry, refresh, listing, targeted sign-out |
| `addscopes.mjs` | widens the spike API key to storage + messaging scopes |
| `storage.mjs` | Phase 3 — image transformations, evidence immutability |
| `storage2.mjs` | Phase 3 — ward-scoped files, and `preview` honouring the ACL |
| `messaging.mjs` | Phase 3 — topics, subscribers, messageId idempotency |
| `deployfn.mjs` | Phase 4 — deploys `fn/create-report` and waits for the build |
| `execfn.mjs` | Phase 4 — the guarded write: direct 401, Function 201, client overruled |
| `events.mjs` | Phase 4 — an event-triggered Function fires on document create |
| `fn/` | the Function sources: the guarded write, an event handler, a runtime probe |

Run against 1.6.2. Permission and auth semantics are stable across 1.x, but
none of this has been run against Cloud.

Four things about this compose cost real time and are worth keeping:
the executor listens on **port 80**; the API and both workers must share
`/storage/functions` and `/storage/builds` with it; the runtimes network must
be external and named exactly `runtimes` (otherwise every execution reports
`timed out during cold start` while the runtime's own log says it started
fine); and MariaDB needs a volume, or `docker compose down` destroys the
project, the collections, the users and every deployed Function.
