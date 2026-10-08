# Setting up the Appwrite project

Three commands. The region is settled (Frankfurt); the tier is the one
thing still to confirm, and the provisioner answers it by running.

---

## The region: decided

**Frankfurt — `https://fra.cloud.appwrite.io/v1`.** The default
everywhere in this directory.

Chosen on latency: of the Appwrite Cloud regions, Frankfurt is much the
closest to Nigeria (Lagos–Frankfurt ≈ 4,500 km, against ≈ 8,500 km to
New York). It is also where the previous Appwrite project ran.

Recorded because it cannot be changed later without migrating everything
a second time, and because the alternative was a data-residency
position. The owner's decision, 2026-10-02, is that NDPA in-country
residency is not a constraint on this deployment. If that is ever
revisited, Cloud is out and the plan moves to self-hosting — which
changes Phases 2, 4 and 6 and brings back the four operational traps
Phase 4 recorded (the executor's port, the shared `/storage` volumes,
the `runtimes` network name, and giving MariaDB a volume).

## The one decision left: which tier

The project needs, at minimum:

| | |
|---|---|
| Teams | **584** — one per ward. Phase 0's whole design rests on ACLs naming a team, so moving an agent between wards is a membership change rather than a rewrite of every document they can see. |
| Messaging topics | **~650** — one per targetable group (56 for states and LGAs, plus per-ward and per-role) |
| Storage buckets | **2** — evidence and profile images, with different ACLs and different retention |
| Collections | **19** |
| Columns | **187** |
| Functions | **7**, three of them on a one-minute schedule |

### What the plan actually allows — run the probe

```
APPWRITE_PROJECT_ID=... APPWRITE_API_KEY=... APPWRITE_DATABASE_ID=... \
node infra/appwrite/provision.mjs --probe
```

`--probe` keeps going past a quota refusal instead of stopping, and
lists every limit at the end. It also creates one throwaway team and one
throwaway topic — the two quotas no pricing page states plainly and the
two this design cannot do without — and deletes them again.

Stopping is right for a real run; probing is right when the question
*is* what the plan allows, because otherwise each limit costs a whole
round trip to discover.

**Measured on the existing Frankfurt project, 2026-10-02 — the plan
refuses four things, and one of them is fatal:**

| | |
|---|---|
| Databases | one, already used by the old build. Pass `APPWRITE_DATABASE_ID` to provision into it. |
| **Functions** | **none available — all seven refused.** Every write, auth's token minting and the whole worker are Functions. There is no version of this design that runs without them. |
| Buckets | none available, so even the one-bucket fallback needs a slot freed. |
| Columns per table | capped; `reports` alone needs 37. |

So this is a billing decision before it is an engineering one: a paid
Cloud plan, or self-hosting. See *Phase 12* in
`../../docs/APPWRITE-MIGRATION.md`.

**The table above is the old project's free tier**
(`6941cdb400050e7249d5`, measured 2 October 2026) and is kept as the
record of it. The plan was upgraded on 7 October, and the work has since
moved to a **different project** (`6ac51e70002ab6238fec`) — so not one of
those four numbers describes what is being provisioned now. `--probe` is
the only thing that does; run it first. The Functions cap is the one the
design could not live with, and the one-database and one-bucket caps are
the two that changed how it provisions.

**One more limit is known from the previous project's own config:**

> Due to Appwrite free tier limits (max 1 bucket), Profile Photos and
> Report Images currently share the same bucket but are logically
> separated by folder paths.

So on that tier the two-bucket plan fails. `--single-bucket` provisions
one shared bucket instead, which is safe while file-level permissions
stay on — see `SINGLE_BUCKET` in `plan.mjs` for what it does and does
not cost. The app follows with `--dart-define PROFILE_IMAGES_BUCKET=...`
and `REPORT_IMAGES_BUCKET=...`.

Since the upgrade that is the fallback, not the Cloud path: a plain run
provisions the two buckets `BUCKETS` declares, whose ids (`report-images`,
`profile-images`) are already the defaults in `AppConfig` and in the admin
panel, so neither needs a define or a variable. `--single-bucket` is still
there for a one-bucket tier, and `APPWRITE_BUCKET_ID` no longer switches
anything on its own — both scripts say so and ignore it when the flag is
absent, because a leftover export silently checking the wrong bucket is
how a verifier stops being one.

One limit came off this list rather than being answered: **messaging
topics**. Phase 3 wanted a topic per targetable group and counted ~650 of
them; Phase 25 creates a topic the first time a device belonging in it
registers, so nothing provisions topics and the quota exposure is the
number of LGAs that actually have users. `--probe` still creates and
deletes one, to learn whether the plan permits any at all.

`provision.mjs` stops the moment the plan refuses something and says so,
rather than burying it in two hundred lines — so running it is also how
the rest of this question gets answered.

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
APPWRITE_PROJECT_ID=... APPWRITE_API_KEY=... \
node infra/appwrite/provision.mjs
```

The endpoint defaults to Frankfurt; `APPWRITE_ENDPOINT` overrides it.

The project in use is **`6ac51e70002ab6238fec`**, and it inherits nothing:
leave `APPWRITE_DATABASE_ID` unset and the plan creates `cradi`. The
earlier project was `6941cdb400050e7249d5` with database
`6941e2c2003705bb5a25` — if you point this at that one instead, set
`APPWRITE_DATABASE_ID` to keep its database id.

**The API key must be a fresh one.** Two server keys from the previous
project are in public git history.

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
node infra/appwrite/phase0.mjs
```

Preflight, then `verify.mjs`, then `cloud-check.mjs`, stopping at the first
failure. Writes no migrated data. Exit **2** means not configured or not
reachable — nothing was contacted, so it says nothing about the project; **1**
means a check failed.

The preflight is its own step because the failure modes are confusable: an
egress policy that does not list the host answers with its own 403 and its own
body, which reads like a wrong endpoint, which reads nothing like a rejected
key — and only the last is about the project. `/health/version` needs no key, so
a failure there is the network or the URL and nothing else, and the run relays
whatever actually answered.

`verify.mjs` on its own is read-only, and exits non-zero when anything is
missing. It checks three
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
