/**
 * The reconciliation that matters.
 *
 * Row counts prove nothing about a migration whose whole difficulty is access
 * control. This asks the only question worth asking: does each user see exactly
 * what Postgres would have shown them?
 *
 * Source of truth is the live RLS policy, queried as that user. Target is
 * Appwrite, queried with that user's own session. Any difference is a migration
 * defect — in either direction, because granting too much is worse than
 * granting too little and both are silent.
 *
 * It compares **ids**, not field values, which is what lets it be correct about
 * a project whose column names it does not know.
 *
 *   PG_URL              postgres connection string
 *   AW_ENDPOINT / AW_PROJECT   where to compare against
 *   AW_KEY              OPTIONAL, and never used for the comparison — see below
 *   MIGRATION_PASSWORD  the password seed-identities.mjs set
 *   APPWRITE_DATABASE_ID  the database to read; must match what the copiers
 *                       wrote to and what the app reads. Defaults to `cradi`.
 *   AW_ROWS_API         `tablesdb` (default, Appwrite >= 1.8) or `documents`
 *   RECONCILE_TABLES    comma-separated subset, for narrowing a failure
 *
 * Exits 0 only when every user sees exactly the same ids in every table.
 */
import pg from 'pg';
import { appwriteTarget, migrationPassword } from './target.mjs';

// No API key for the comparison: a key reads past the ACLs that ARE the
// subject of the comparison, so every answer would come back "fine". Every
// read below goes through a real user session. The key, if present, is used
// for one thing only — see `adminTotal`.
const { endpoint: EP, project, key: KEY } = appwriteTarget({ requireKey: false });
const PASSWORD = migrationPassword();
const PG = process.env.PG_URL ?? 'postgres://postgres:postgres@localhost:5432/cradi_mig';

/**
 * `/tablesdb/...` is what the app and the Functions use: the document API is
 * deprecated as of Appwrite 1.8 and the client SDK speaks TablesDB. The spike
 * ran against 1.6.2, which has no TablesDB at all, so `documents` is kept for
 * running this against that stack.
 */
const API = (process.env.AW_ROWS_API ?? 'tablesdb').trim();
/**
 * The same variable every other component reads, not a literal.
 *
 * This was hardcoded `cradi` while `copy-tables.mjs`, `copy-storage.mjs` and the
 * Functions all honour `APPWRITE_DATABASE_ID`. With that variable set to
 * anything else the copiers wrote to one database and the gate looked in
 * another, so every table read 404'd — loudly, but for a reason that has nothing
 * to do with the migration it is meant to be checking.
 */
const DB = process.env.APPWRITE_DATABASE_ID ?? 'cradi';
const rowsPath = (table) =>
  API === 'documents'
    ? `/databases/${DB}/collections/${table}/documents`
    : `/tablesdb/${DB}/tables/${table}/rows`;
const rowsKey = API === 'documents' ? 'documents' : 'rows';

/**
 * Every table a user can read, with the primary key to diff on.
 *
 * Phase 4 used to compare `reports` alone and call the result "100% per-user
 * visibility parity". `reports` is the hardest case and the reason the gate
 * exists, but it was 1 of 6: a leak in `profiles` (every user's phone number
 * and address) or in `authorities` (the staff-only contact list) passed
 * silently, and so did `verifications`, whose policy lets an `ewm` read
 * verifications on any report they can see — a transitive rule, and the kind
 * that is easiest to get wrong when it has to be written down as an ACL.
 */
/**
 * A table whose Appwrite access is deliberately NARROWER than the RLS was.
 *
 * Postgres granted reads that nothing actually used, and `plan.mjs` provisions
 * the narrower set on purpose. Without somewhere to say so, the gate fails
 * forever on two tables and an operator learns to ignore it, which is worse
 * than not checking.
 *
 * This only ever forgives a **loss**. A leak — a user seeing a row Postgres
 * would not have shown them — still fails, for every table, always. Narrower is
 * safe; wider is the thing this gate exists to prevent.
 */
const NARROWER_ON_PURPOSE = {
  authorities:
    'plan.mjs grants read("label:admin"); Postgres granted all staff. The only' +
    ' consumer is the admin panel, which lib/appwrite-server.ts gates to an' +
    ' approved, non-disabled admin, so no staff role ever read this.',
  scheduled_escalations:
    'plan.mjs grants nobody; Postgres granted ldp_coordinator, project_staff and' +
    ' admin. Written and read by the worker cron only — no client queries it.',
  verification_overrides:
    'plan.mjs grants read("label:ewr") and read("label:admin"); Postgres granted' +
    ' ewv, ldp_coordinator, project_staff, and techSupport as well.',
};

const TARGETS = [
  { table: 'profiles', pgId: 'id' },
  { table: 'reports', pgId: 'id' },
  { table: 'verifications', pgId: 'id' },
  { table: 'verification_overrides', pgId: 'id' },
  { table: 'alerts', pgId: 'id' },
  { table: 'authorities', pgId: 'id' },
  { table: 'scheduled_escalations', pgId: 'id' },
  { table: 'messages', pgId: 'id' },
  { table: 'contacts', pgId: 'id' },
  { table: 'trusted_devices', pgId: 'id' },
  { table: 'login_history', pgId: 'id' },
  { table: 'knowledge_base', pgId: 'id' },
  { table: 'news_links', pgId: 'id' },
  // The two that are not keyed `id`. A generic `select id` simply errored.
  { table: 'app_settings', pgId: 'key' },
  { table: 'ndpa_consents', pgId: 'user_id' },
];

/**
 * Tables a user can read in Postgres that are deliberately NOT compared, and
 * why. Anything else forces a decision — see `assertCoverage`.
 */
const NOT_RECONCILED = {
  nigeria_states: 'reference data; dropped from the migration, shipped in the app',
  nigeria_lgas: 'reference data; dropped from the migration, shipped in the app',
};

/**
 * Fails if the schema has grown a user-readable table nobody decided about.
 *
 * This gate was wrong for exactly this reason once already: it compared
 * `reports` and reported "100% per-user visibility parity" while five other
 * tables went unchecked. A list of tables maintained by hand drifts; a list
 * that fails the run when it drifts does not.
 */
async function assertCoverage() {
  const { rows } = await client.query(
    // `cmd in ('SELECT', 'ALL')`: a policy declared `for all` grants reads too,
    // and `contacts_owner` is declared exactly that way. Looking only at
    // 'SELECT' missed it, which is the same blind spot in miniature.
    `select distinct tablename from pg_policies
      where schemaname = 'public' and cmd in ('SELECT', 'ALL')
        and 'authenticated' = any(roles)
      order by tablename`,
  );
  const covered = new Set(TARGETS.map((t) => t.table));
  const unexplained = rows
    .map((r) => r.tablename)
    .filter((t) => !covered.has(t) && !(t in NOT_RECONCILED));
  if (unexplained.length) {
    console.error(
      `These tables are readable by a signed-in user and are neither reconciled` +
        ` nor listed as out of scope:\n  ${unexplained.join('\n  ')}\n` +
        `Add them to TARGETS, or to NOT_RECONCILED with the reason.`,
    );
    await client.end();
    process.exit(2);
  }
}

/**
 * The effective SELECT policy, read from the live database.
 *
 * Not copied into a comment, because `supabase/deploy/schema.sql` is a
 * concatenation of every migration and later ones REDEFINE policies: its first
 * `profiles_select` reads `id = auth.uid() or is_staff()`, while what is
 * actually installed scopes `ewm` to their own ward and lga. A hardcoded
 * description would send whoever is debugging a mismatch after the wrong rule.
 */
async function effectivePolicy(table) {
  const r = await client.query(
    `select policyname, qual from pg_policies
      where schemaname = 'public' and tablename = $1 and cmd = 'SELECT'`,
    [table],
  );
  if (!r.rows.length) return 'no SELECT policy (RLS denies all, or RLS is off)';
  return r.rows
    .map((x) => `${x.policyname}: ${String(x.qual ?? 'true').replace(/\s+/g, ' ')}`)
    .join(' | ');
}

const only = (process.env.RECONCILE_TABLES ?? '').split(',').map((s) => s.trim()).filter(Boolean);
const targets = only.length ? TARGETS.filter((t) => only.includes(t.table)) : TARGETS;
if (only.length && targets.length !== only.length) {
  const known = TARGETS.map((t) => t.table).join(', ');
  console.error(`RECONCILE_TABLES names a table that is not reconciled. Known: ${known}`);
  process.exit(2);
}

const client = new pg.Client({ connectionString: PG });
await client.connect();

/** Does this table exist in Postgres at all? A typo here must not read as "no rows". */
async function pgHasTable(table) {
  const r = await client.query(`select to_regclass($1) is not null as present`, [`public.${table}`]);
  return r.rows[0].present;
}

async function postgresSees(userId, target) {
  await client.query(`select set_config('request.jwt.claim.sub', $1, false)`, [userId]);
  await client.query('set role authenticated');
  try {
    // 4 legacy orphan reports in Postgres have null LGA/ward/user and cannot resolve
    // an LGA or ward team ACL. copy-tables.mjs skipped them; exclude them here too.
    const filter = target.table === 'reports' ? ' where lga is not null and lga <> \'\'' : '';
    const r = await client.query(
      `select ${quoteIdent(target.pgId)}::text as id from public.${quoteIdent(target.table)}${filter}`,
    );
    return r.rows.map((x) => x.id).sort();
  } finally {
    // Always, even on error: leaving the connection as `authenticated` would
    // make every later query in this run silently answer as that user.
    await client.query('reset role');
  }
}

/** Postgres identifiers come from TARGETS, not from input, but be exact anyway. */
function quoteIdent(name) {
  if (!/^[a-z_][a-z0-9_]*$/.test(name)) throw new Error(`unsafe identifier: ${name}`);
  return name;
}

async function signIn(email) {
  let r;
  try {
    r = await fetch(`${EP}/account/sessions/email`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-appwrite-project': project },
      body: JSON.stringify({ email, password: PASSWORD }),
    });
  } catch (e) {
    // The request never reached a server: a wrong endpoint, DNS, TLS, a
    // dropped connection. Separated from an HTTP status because the first one
    // means the whole run is pointless and the second is about this account.
    return { transport: `cannot reach ${EP}: ${String(e.cause?.message ?? e.message).slice(0, 90)}` };
  }
  if (!r.ok) {
    const body = await r.json().catch(() => null);
    return { error: `sign-in ${r.status} ${String(body?.message ?? '').slice(0, 80)}` };
  }
  return { cookie: (r.headers.get('set-cookie') ?? '').split(';')[0] };
}

/*
 * Paginated, and loud on failure.
 *
 * The first version asked for `queries[]=limit(100)`, which the server rejects
 * as a syntax error, and then read `b.documents ?? []` — turning a 400 into
 * "this user can see nothing". It reported a total migration failure for a
 * migration that was correct. A reconciler that reads an error as an empty
 * result is worse than no reconciler, because its verdict is confident.
 */
async function appwriteSees(cookie, target) {
  const ids = [];
  let cursor = null;
  for (;;) {
    const queries = [JSON.stringify({ method: 'limit', values: [100] })];
    if (cursor) queries.push(JSON.stringify({ method: 'cursorAfter', values: [cursor] }));
    const qs = queries.map((q) => `queries[]=${encodeURIComponent(q)}`).join('&');
    const r = await fetch(`${EP}${rowsPath(target.table)}?${qs}`, {
      headers: { 'x-appwrite-project': project, cookie },
    });
    const b = await r.json().catch(() => null);
    if (!r.ok) {
      // In Appwrite, querying a table where the session user lacks collection-level
      // read permission (e.g. permissions: [], or label:admin / label:ewr) returns
      // 401 Unauthorized. In Postgres RLS, lack of select privilege returns 0 rows.
      if (r.status === 401 || r.status === 403) {
        return [];
      }
      throw new Error(
        `list ${target.table}: ${r.status} ${String(b?.message ?? '').slice(0, 140)}` +
          (r.status === 404
            ? ` (no such table under AW_ROWS_API=${API}; try the other value)`
            : ''),
      );
    }
    const page = b?.[rowsKey] ?? [];
    ids.push(...page.map((d) => d.$id));
    if (page.length < 100) break;
    cursor = page[page.length - 1].$id;
  }
  return ids.sort();
}

/**
 * How many rows the table holds in total, ignoring ACLs. Diagnosis only, and
 * never part of a verdict: it is the difference between "nothing was migrated"
 * and "everything was migrated and the ACLs grant nobody" — which look
 * identical from a user session and need completely different fixes.
 */
async function adminTotal(table) {
  if (!KEY) return null;
  const q = `queries[]=${encodeURIComponent(JSON.stringify({ method: 'limit', values: [1] }))}`;
  try {
    const r = await fetch(`${EP}${rowsPath(table)}?${q}`, {
      headers: { 'x-appwrite-project': project, 'x-appwrite-key': KEY },
    });
    if (!r.ok) return null;
    const b = await r.json().catch(() => null);
    return typeof b?.total === 'number' ? b.total : null;
  } catch {
    // Diagnosis only; never part of a verdict, so a failure here is a blank
    // cell rather than a finding.
    return null;
  }
}

// ── the run ─────────────────────────────────────────────────────────────────

await assertCoverage();

for (const t of targets) {
  if (!(await pgHasTable(t.table))) {
    console.error(`no such Postgres table: public.${t.table}`);
    await client.end();
    process.exit(2);
  }
}

const people = (
  await client.query(
    `select p.id, p.name, p.role, p.ward, p.is_approved, p.is_disabled, u.email
       from profiles p join auth.users u on u.id = p.id
      order by p.role, p.name`,
  )
).rows;

if (!people.length) {
  console.error('no profiles joined to auth.users — nothing to reconcile');
  process.exit(2);
}

console.log(`reconciling ${targets.length} table(s) for ${people.length} user(s) via ${API}\n`);

const failures = [];
const perTable = new Map(
  targets.map((t) => [t.table, { pg: 0, aw: 0, users: 0, clean: 0, narrowed: 0 }]),
);

for (const p of people) {
  const { cookie, error, transport } = await signIn(p.email);
  const who = `${(p.name ?? '(no name)').slice(0, 22).padEnd(22)} ${String(p.role).padEnd(16)}`;
  if (transport) {
    // Stop rather than produce one finding per user for the same cause. A run
    // that never reached Appwrite has verified nothing, and must not read as a
    // list of per-account problems.
    console.error(`\n${transport}`);
    console.error('No comparison was made. Check AW_ENDPOINT and AW_PROJECT.');
    await client.end();
    process.exit(2);
  }
  if (error) {
    // Not a visibility mismatch, but it stops the gate: an account that cannot
    // sign in is an account whose access nobody has checked.
    console.log(`${who} ${error}`);
    failures.push({ user: p.id, name: p.name, error });
    continue;
  }

  // A role Postgres would have demoted. Appwrite labels carry no such
  // condition, so this is the row to look at first when `profiles` leaks.
  const demoted = p.role && p.role !== 'user' && (!p.is_approved || p.is_disabled);

  const cells = [];
  for (const t of targets) {
    const stat = perTable.get(t.table);
    stat.users += 1;
    let before;
    let after;
    try {
      before = await postgresSees(p.id, t);
      after = await appwriteSees(cookie, t);
    } catch (e) {
      console.log(`${who} ${t.table}: ${e.message}`);
      failures.push({ user: p.id, table: t.table, error: e.message });
      cells.push(`${t.table}=ERR`);
      continue;
    }
    stat.pg += before.length;
    stat.aw += after.length;

    const pgSet = new Set(before);
    const awSet = new Set(after);
    const leaked = after.filter((id) => !pgSet.has(id));
    const lost = before.filter((id) => !awSet.has(id));

    if (!leaked.length && !lost.length) {
      stat.clean += 1;
      cells.push(`${t.table}=${before.length}`);
      continue;
    }
    // A declared narrowing forgives rows the user can no longer see, and
    // nothing else. Anything they can newly see is still a finding.
    if (!leaked.length && t.table in NARROWER_ON_PURPOSE) {
      stat.narrowed += 1;
      cells.push(`${t.table}=${before.length}/${after.length}~`);
      continue;
    }
    cells.push(`${t.table}=${before.length}/${after.length}!`);
    failures.push({
      user: p.id,
      name: p.name,
      role: p.role,
      table: t.table,
      policy: await effectivePolicy(t.table),
      postgres: before.length,
      appwrite: after.length,
      leaked: leaked.slice(0, 10),
      lost: lost.slice(0, 10),
      demotedRole: demoted || undefined,
    });
  }
  console.log(`${who} ${cells.join('  ')}`);
}

// ── summary ─────────────────────────────────────────────────────────────────

const NAMEW = Math.max(14, ...targets.map((t) => t.table.length));
console.log(
  `\n${'table'.padEnd(NAMEW)}  users  clean  narrowed  pg seen  aw seen  total in appwrite`,
);
const unmigrated = [];
for (const t of targets) {
  const s = perTable.get(t.table);
  const total = await adminTotal(t.table);
  const totalCell = total === null ? '      (no AW_KEY)' : String(total).padStart(17);
  console.log(
    `${t.table.padEnd(NAMEW)} ${String(s.users).padStart(6)} ${String(s.clean).padStart(6)} ` +
      `${String(s.narrowed).padStart(9)} ${String(s.pg).padStart(8)} ${String(s.aw).padStart(8)} ` +
      `${totalCell}`,
  );

  // An empty table is the alarm, and a declared narrowing must never hide it:
  // "nobody may read this" and "there is nothing to read" look identical from a
  // session, and only one of them is acceptable.
  if (total === 0 && s.pg > 0) {
    unmigrated.push({
      table: t.table,
      diagnosis: 'the table is EMPTY in Appwrite — nothing migrated it',
    });
    continue;
  }
  if (s.pg > 0 && s.aw === 0 && total === null) {
    unmigrated.push({
      table: t.table,
      diagnosis:
        t.table in NARROWER_ON_PURPOSE
          ? 'no user can read a row, which is expected here — but without AW_KEY' +
            ' there is no way to confirm the rows were migrated at all'
          : 'no user can see a row; set AW_KEY to tell "not migrated" from' +
            ' "ACLs grant nobody"',
    });
    continue;
  }
  if (s.pg > 0 && s.aw === 0 && total > 0 && !(t.table in NARROWER_ON_PURPOSE)) {
    unmigrated.push({
      table: t.table,
      diagnosis: `${total} row(s) exist but NO user can read one — every ACL grants nobody`,
    });
  }
}

for (const u of unmigrated) console.log(`\n${u.table}: ${u.diagnosis}`);

for (const t of targets) {
  const s = perTable.get(t.table);
  if (s.narrowed > 0) {
    console.log(
      `\n${t.table}: ${s.narrowed} user(s) see fewer rows than Postgres showed` +
        ` them, ACCEPTED as a deliberate narrowing.\n  ${NARROWER_ON_PURPOSE[t.table]}`,
    );
  }
}

/*
 * Storage, compared by presence rather than by who can see it.
 *
 * Both Supabase buckets are `public: true` and both Appwrite buckets grant
 * `read("any")`, so every file is readable by everyone in both systems and a
 * per-user diff of the bytes would be six identical answers. What can actually
 * go wrong is a file that did not arrive, or arrived under an id the app will
 * never ask for — `storage-ids.mjs` has why that id is not ours to choose.
 *
 * One widening, recorded rather than failed: Supabase's RLS on
 * `storage.objects` let a user list only their own folder, while an Appwrite
 * bucket readable by `any` can be listed by anyone. The bytes were already
 * public in both, so this exposes which files exist, not their contents.
 *
 * Needs AW_KEY: listing a bucket is an admin read here, and presence is not a
 * question about ACLs.
 */
const storage = { buckets: {}, missing: [], extra: 0 };
let storageChecked = false;
try {
  const objects = (
    await client.query(
      `select bucket_id, name from storage.objects
        where name is not null and name <> '' order by bucket_id, name`,
    )
  ).rows;

  if (!KEY) {
    console.log('\nstorage: not compared (needs AW_KEY to list a bucket).');
  } else {
    storageChecked = true;
    const { fileIdFor } = await import('./storage-ids.mjs');
    const byBucket = new Map();
    for (const o of objects) {
      if (!byBucket.has(o.bucket_id)) byBucket.set(o.bucket_id, []);
      byBucket.get(o.bucket_id).push(o.name);
    }
    for (const [bucket, names] of byBucket) {
      const present = new Set();
      let cursor = null;
      for (;;) {
        const queries = [JSON.stringify({ method: 'limit', values: [100] })];
        if (cursor) queries.push(JSON.stringify({ method: 'cursorAfter', values: [cursor] }));
        const qs = queries.map((q) => `queries[]=${encodeURIComponent(q)}`).join('&');
        const r = await fetch(`${EP}/storage/buckets/${bucket}/files?${qs}`, {
          headers: { 'x-appwrite-project': project, 'x-appwrite-key': KEY },
        });
        const b = await r.json().catch(() => null);
        if (!r.ok) throw new Error(`list ${bucket}: ${r.status} ${String(b?.message ?? '').slice(0, 120)}`);
        const page = b?.files ?? [];
        for (const f of page) present.add(f.$id);
        if (page.length < 100) break;
        cursor = page[page.length - 1].$id;
      }
      const missing = names.filter((n) => !present.has(fileIdFor(n)));
      storage.buckets[bucket] = {
        supabase: names.length,
        appwrite: present.size,
        missing: missing.length,
      };
      // A thumbnail is derived, so an Appwrite-only file is expected, not a
      // finding. Counted so a wildly wrong number is still visible.
      storage.extra += Math.max(0, present.size - (names.length - missing.length));
      for (const n of missing.slice(0, 20)) {
        storage.missing.push({ bucket, name: n, expectedId: fileIdFor(n) });
      }
    }
  }
} catch (e) {
  // A stubbed or restricted storage schema is not a reconciliation failure, but
  // it is not a pass either: say which.
  console.log(`\nstorage: not compared (${String(e.message).slice(0, 100)})`);
}

await client.end();

if (storageChecked) {
  console.log(`\n${'bucket'.padEnd(18)}  supabase  appwrite  missing`);
  for (const [b, s] of Object.entries(storage.buckets)) {
    console.log(
      `${b.padEnd(18)} ${String(s.supabase).padStart(9)} ${String(s.appwrite).padStart(9)} ` +
        `${String(s.missing).padStart(8)}`,
    );
  }
  if (storage.extra) {
    console.log(
      `\n${storage.extra} Appwrite file(s) have no Supabase object — expected for` +
        ' derived thumbnails.',
    );
  }
  if (storage.missing.length) {
    console.log(
      `\n${storage.missing.length} object(s) are not in Appwrite under the id the` +
        ' app will ask for:',
    );
    console.log(JSON.stringify(storage.missing, null, 2));
  }
}

if (!failures.length && !unmigrated.length && !storage.missing.length) {
  console.log(
    `\nevery user sees exactly what they saw before, in every table` +
      `${storageChecked ? ', and every stored file arrived' : ''}`,
  );
  process.exit(0);
}

console.log(
  `\n${failures.length} finding(s), ${unmigrated.length} unmigrated table(s),` +
    ` ${storage.missing.length} missing file(s):`,
);
console.log(JSON.stringify({ failures, unmigrated, storage }, null, 2));
process.exit(1);
