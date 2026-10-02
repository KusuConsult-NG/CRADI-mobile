# Setting up the Appwrite project

Three commands, two decisions. The commands are here; **the decisions are
not mine to make** and both have been open since Phase 1 of the migration.

---

## The two decisions, first

### 1. Which region

The endpoint carries it — `https://fra.cloud.appwrite.io/v1` is
Frankfurt, which is where the old project was. Whether that is lawful
under the NDPA for Nigerian citizens' hazard reports, locations and phone
numbers is a **compliance question about personal data belonging to real
people**, and it is not one to settle from a provisioning script.

It is also not a detail that can be changed later: moving an Appwrite
Cloud project between regions means a second migration of everything this
one migrates.

If in-country residency is required, Cloud is out and the whole plan moves
to self-hosting — which changes Phases 2, 4 and 6 materially, and brings
back the four operational traps Phase 4 recorded (the executor's port, the
shared `/storage` volumes, the `runtimes` network name, and giving MariaDB
a volume).

### 2. Which tier

The project needs, at minimum:

| | |
|---|---|
| Teams | **584** — one per ward. Phase 0's whole design rests on ACLs naming a team, so moving an agent between wards is a membership change rather than a rewrite of every document they can see. |
| Messaging topics | **~650** — one per targetable group (56 for states and LGAs, plus per-ward and per-role) |
| Storage buckets | **2** — evidence and profile images, with different ACLs and different retention |
| Collections | **19** |
| Columns | **187** |
| Functions | **7**, three of them on a one-minute schedule |

`provision.mjs` stops the moment the plan refuses something and says so,
rather than burying it in two hundred lines — so running it is also how
this question gets answered, if nobody can answer it from the pricing
page.

---

## The commands

### 0. In the console, by hand

Create the project (picking the region — see above) and a **server API
key** with, at minimum:

```
databases.read  databases.write
collections.read collections.write
attributes.read attributes.write
indexes.read indexes.write
documents.read documents.write
buckets.read buckets.write
functions.read functions.write
teams.read teams.write
users.read users.write
```

The key is only used by the provisioner and by the Functions; it must
never reach the app. The app gets the endpoint and project id, which are
not secrets.

### 1. See the plan, offline

```
node infra/appwrite/provision.mjs --dry-run
```

Needs no credentials and no network — it prints every object it would
create (237 of them) against an imagined empty project.

### 2. Apply it

```
APPWRITE_ENDPOINT=https://<region>.cloud.appwrite.io/v1 \
APPWRITE_PROJECT_ID=... \
APPWRITE_API_KEY=... \
node infra/appwrite/provision.mjs
```

**Idempotent**: every step checks before it writes and prints
`created` / `exists`. A half-finished run is resumed by running it again,
which is not a nicety — Phase 4 lost an entire spike project to
`docker compose down` on a volumeless MariaDB, and the only reason that
was cheap is that the spike was scripted.

**It never deletes.** A column in the project that is not in the plan is
reported with a `?` and left alone. Dropping a column drops its data, and
this will be run against a project holding live reports.

`--only=collections` (or `database`, `buckets`, `functions`) narrows it.

### 3. Deploy the Function code

The provisioner creates the Functions but cannot push code — that is the
Appwrite CLI, from `functions/cradi`:

```
appwrite push function --function-id write
appwrite push function --function-id auth
appwrite push function --function-id operation
appwrite push function --function-id on-write
appwrite push function --function-id drain
appwrite push function --function-id escalate
appwrite push function --function-id reconcile
```

Then set each one's variables (`APPWRITE_API_KEY`, `APPWRITE_DATABASE_ID`,
and `TERMII_API_KEY` / `TERMII_SENDER_ID` on `drain`). See
`functions/cradi/README.md`.

### 4. Check it

```
APPWRITE_ENDPOINT=... APPWRITE_PROJECT_ID=... APPWRITE_API_KEY=... \
node infra/appwrite/verify.mjs
```

Read-only, and exits non-zero when anything is missing. It checks three
things a bare existence check would call fine: a column stuck in
`processing` (present, and rejects every write), a Function created but
never deployed (answers every call with a 500 and looks healthy in the
console), and a schedule that does not match the plan.

---

## Where the plan comes from

`plan.mjs` is the declaration. Its **columns are generated**, not written
by hand:

```
node infra/appwrite/extract-schema.mjs > infra/appwrite/columns.json
```

reads `supabase/migrations/` — which *is* the live database — and derives
the 187 Appwrite columns from it. Hand-writing them would have been
quicker and would have created a second source of truth for a schema that
already has one. `functions/cradi/test/plan.test.mjs` fails if the
committed file falls behind the migrations, so a column added to Postgres
and forgotten here is a red CI run rather than a write the server rejects
at 3am with the report already typed in.

Everything else in `plan.mjs` traces to a phase of
`docs/APPWRITE-MIGRATION.md`: the collection list and write rules to
Phase 1, the document ACLs to Phase 0, buckets and topics to Phase 3, the
Functions to Phases 10 and 11.

## What this does not do

- **Teams and topics.** 584 teams and ~650 topics are created from the
  migrated data, not from a static list — `docs/appwrite-spike/migrate/`
  creates each ward team as it writes the first document that names it.
  Creating them here would mean guessing which wards have members.
- **Seed data.** `app_settings`, `knowledge_base`, `authorities` and
  `news_links` come across in the migration, not from the plan.
- **Anything destructive.** No deletes, ever. If the plan and the project
  disagree, the project wins and you are told.
