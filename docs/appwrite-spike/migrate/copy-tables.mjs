/**
 * The six collections `migrate.mjs` never wrote, copied into the schema the
 * project actually has.
 *
 * `alerts`, `authorities`, `app_settings`, `scheduled_escalations`,
 * `knowledge_base`, `news_links`. Phase 4's reconciler reported each of them as
 * holding rows a signed-in user can read in Postgres and nothing at all in
 * Appwrite — because nothing migrated them.
 *
 * Three sources of truth, all imported rather than restated:
 *
 *   - **columns** from `infra/appwrite/columns.json`, which `extract-schema.mjs`
 *     derives from the migrations and `verify.mjs` holds the project to. A
 *     Postgres column whose camelCase name is not in there is not written, and
 *     is reported — it has nowhere to go, and finding that out from a 400 at
 *     3am is the thing this avoids.
 *   - **the camelCase rule** from `extract-schema.mjs`'s own `toField`, so the
 *     names here cannot drift from the names provisioned.
 *   - **the ACL** from `policy.js`'s `RULES`, so a migrated row carries exactly
 *     what the `client` Function stamps on a row created afterwards.
 *
 * It writes through `/tablesdb/…/tables/…/rows`, which is what the app, the
 * admin and the Functions use. (`migrate.mjs`'s three collections still write
 * snake_case through the deprecated documents API against the spike's own
 * schema — see the note in `docs/CUTOVER-RUNBOOK.md` Phase 3. They are not
 * retargeted here because `verifications` denormalises `ward`/`lga`/`state`
 * onto the row for its ACL and `columns.json` has no such columns, so doing it
 * faithfully needs a `plan.mjs` change.)
 *
 * Idempotent: the Postgres primary key becomes the Appwrite `$id`, so a re-run
 * answers 409 rather than duplicating.
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import pg from 'pg';
import { appwriteTarget } from './target.mjs';
import { toField } from '../../../infra/appwrite/extract-schema.mjs';
import { RULES } from '../../../functions/cradi/src/lib/policy.js';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, '..', '..', '..');
const COLUMNS = JSON.parse(readFileSync(resolve(REPO, 'infra/appwrite/columns.json'), 'utf8'));

const PG = process.env.PG_URL ?? 'postgres://postgres:postgres@localhost:5432/cradi_mig';
const DB = process.env.APPWRITE_DATABASE_ID ?? 'cradi';
const rowsPath = (table) => `/tablesdb/${DB}/tables/${table}/rows`;

/**
 * The six, with the Postgres primary key that becomes `$id`.
 *
 * `app_settings` is keyed by `key` and not by `id` — and `key` is also a
 * planned column, so it is written as data *and* used as the row id. Nothing
 * here special-cases the key: a column is written when the plan has it, which
 * gets that right without a rule about it.
 */
export const TABLES = [
  { table: 'alerts', pgId: 'id' },
  { table: 'authorities', pgId: 'id' },
  { table: 'app_settings', pgId: 'key' },
  { table: 'scheduled_escalations', pgId: 'id' },
  { table: 'knowledge_base', pgId: 'id' },
  { table: 'news_links', pgId: 'id' },
];

/** Appwrite's row id rule: 36 chars, no leading special character. */
const ROW_ID = /^[a-zA-Z0-9][a-zA-Z0-9._-]{0,35}$/;

/**
 * Postgres value -> what Appwrite will accept for that column type.
 *
 * `null` means "leave the column unset", which is why it is returned rather
 * than written: Appwrite rejects an explicit null on a required column with a
 * different error than a missing one, and the required check below is clearer.
 */
export function coerce(value, column) {
  if (value === null || value === undefined) return null;
  if (column.array) {
    const list = Array.isArray(value) ? value : [value];
    return list.map((v) => coerce(v, { ...column, array: false }));
  }
  switch (column.type) {
    case 'boolean':
      return Boolean(value);
    case 'integer':
      return Number.parseInt(String(value), 10);
    case 'double':
      return Number(value);
    case 'datetime':
      // `pg` hands back a Date for timestamptz. Appwrite wants ISO-8601.
      return (value instanceof Date ? value : new Date(String(value))).toISOString();
    default: {
      // jsonb arrives as a parsed object; the plan stores it as a string.
      const s = typeof value === 'object' ? JSON.stringify(value) : String(value);
      // A value longer than the column cannot be written, and silently
      // truncating migrated data is worse than refusing to.
      if (column.size && s.length > column.size) {
        throw new Error(`value is ${s.length} chars, column holds ${column.size}`);
      }
      return s;
    }
  }
}

/** The ACL the `client` Function would stamp, or none when it owns no rule. */
export function aclFor(table, rowId) {
  const rule = RULES[table];
  if (typeof rule?.acl !== 'function') return null;
  return rule.acl({ documentId: rowId });
}

/**
 * Builds the row body for one Postgres row, or explains why it cannot.
 *
 * Separated from the writing so the mapping can be checked without a server,
 * and so a whole table can be validated before anything is sent.
 */
export function buildRow(row, { table, pgId }) {
  const planned = new Map((COLUMNS[table] ?? []).map((c) => [c.key, c]));
  if (!planned.size) return { error: `no columns planned for ${table}` };

  const rowId = String(row[pgId] ?? '');
  if (!ROW_ID.test(rowId)) {
    return { error: `primary key ${JSON.stringify(rowId)} is not a usable Appwrite row id` };
  }

  const data = {};
  const unplanned = [];
  for (const [name, value] of Object.entries(row)) {
    const key = toField(name);
    const column = planned.get(key);
    if (!column) {
      // The primary key becoming `$id` is expected, not a gap.
      if (name !== pgId) unplanned.push(name);
      continue;
    }
    try {
      const v = coerce(value, column);
      if (v !== null) data[key] = v;
    } catch (e) {
      return { error: `${name}: ${e.message}` };
    }
  }

  const missing = [...planned.values()]
    .filter((c) => c.required && data[c.key] === undefined)
    .map((c) => c.key);
  if (missing.length) return { error: `required column(s) unset: ${missing.join(', ')}` };

  return { rowId, data, permissions: aclFor(table, rowId), unplanned };
}

export async function run({ log = console.log } = {}) {
  const { aw } = appwriteTarget();
  const client = new pg.Client({ connectionString: PG });
  await client.connect();

  const counts = {};
  const failures = [];
  const unplannedColumns = {};

  for (const target of TABLES) {
    const { table, pgId } = target;
    const { rows } = await client.query(`select * from public.${table} order by ${pgId}`);
    const stat = { source: rows.length, created: 0, exists: 0, failed: 0 };
    counts[table] = stat;

    for (const row of rows) {
      const built = buildRow(row, target);
      if (built.error) {
        stat.failed += 1;
        failures.push({ table, id: String(row[pgId]), error: built.error });
        continue;
      }
      if (built.unplanned?.length) {
        // Reported once per table, not once per row.
        unplannedColumns[table] = [
          ...new Set([...(unplannedColumns[table] ?? []), ...built.unplanned]),
        ];
      }
      const r = await aw(rowsPath(table), {
        method: 'POST',
        body: JSON.stringify({
          rowId: built.rowId,
          data: built.data,
          ...(built.permissions ? { permissions: built.permissions } : {}),
        }),
      });
      if (r.status === 201) stat.created += 1;
      else if (r.status === 409) stat.exists += 1;
      else {
        stat.failed += 1;
        failures.push({
          table,
          id: built.rowId,
          error: `${r.status} ${String(r.body?.message ?? '').slice(0, 140)}`,
        });
      }
    }
    log(
      `${table.padEnd(22)} ${stat.source} row(s): ${stat.created} created, ` +
        `${stat.exists} already there, ${stat.failed} failed`,
    );
  }

  await client.end();
  return { counts, failures, unplannedColumns };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const { counts, failures, unplannedColumns } = await run();
  console.log(JSON.stringify({ counts, unplannedColumns }, null, 2));
  if (Object.keys(unplannedColumns).length) {
    console.error(
      '\nPostgres columns with no column in the plan — their data was NOT written:',
    );
    for (const [t, cols] of Object.entries(unplannedColumns)) {
      console.error(`  ${t}: ${cols.join(', ')}`);
    }
    console.error('Add them to the migrations and re-run extract-schema.mjs, or accept the loss.');
  }
  if (failures.length) {
    console.error(`\n${failures.length} row(s) failed:`);
    console.error(JSON.stringify(failures.slice(0, 20), null, 2));
    process.exitCode = 1;
  }
}
