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

Run against 1.6.2. Permission and auth semantics are stable across 1.x, but
none of this has been run against Cloud.
