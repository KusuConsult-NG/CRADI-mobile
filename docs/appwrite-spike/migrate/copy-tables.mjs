/**
 * Every collection, copied into the schema the project actually has.
 *
 * `migrate.mjs` wrote `profiles`, `reports` and `verifications` in snake_case
 * through the deprecated `/databases/…/collections/…/documents` API, against
 * the ad-hoc schema `prep.mjs` creates. The project this repository provisions
 * has camelCase columns under `/tablesdb/…/tables/…/rows`, so those writes
 * could not land in it at all. The other six had nothing writing them.
 *
 * Both halves are here now, in dependency order, through one mechanism.
 *
 * Four sources of truth, all imported rather than restated:
 *
 *   - **columns** from `plan.mjs`'s `COLLECTIONS` — not `columns.json`. That
 *     file is derived from the migrations alone, and the plan adds the
 *     denormalised columns Appwrite needs and Postgres never had
 *     (`verifications.state`, `reports.userName`, …). Reading the narrower one
 *     is what made those look unplanned, and is why this was thought to need a
 *     `plan.mjs` change: it does not. A Postgres column with no planned column
 *     is still reported rather than dropped in silence.
 *   - **the camelCase rule** from `extract-schema.mjs`'s own `toField`, so the
 *     names here cannot drift from the names provisioned.
 *   - **the ACL**: `policy.js`'s `RULES` for the six, and `migrate.mjs`'s
 *     `*Permissions` builders for the three. Those two disagree, deliberately
 *     — see `ACL_SOURCE` below.
 *   - **the denormalised values** from the same expressions `write.js` uses, so
 *     a migrated row and one created afterwards carry the same thing.
 *
 * Idempotent: the Postgres primary key becomes the Appwrite `$id`, so a re-run
 * answers 409 rather than duplicating.
 */
import pg from 'pg';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import { appwriteTarget } from './target.mjs';
import { toField } from '../../../infra/appwrite/extract-schema.mjs';
import { RULES } from '../../../functions/cradi/src/lib/policy.js';
import { COLLECTIONS } from '../../../infra/appwrite/plan.mjs';
import {
  profilePermissions,
  reportPermissions,
  verificationPermissions,
} from './migrate.mjs';

/** What `provision.mjs` actually creates, denormalised columns included. */
const COLUMNS = Object.fromEntries(COLLECTIONS.map((c) => [c.id, c.columns]));

const PG = process.env.PG_URL ?? 'postgres://postgres:postgres@localhost:5432/cradi_mig';
const DB = process.env.APPWRITE_DATABASE_ID ?? 'cradi';
const rowsPath = (table) => `/tablesdb/${DB}/tables/${table}/rows`;

/**
 * Where each collection's ACL comes from, and why the two sources disagree.
 *
 * `policy.js`'s `RULES` is what the `client` Function stamps on a row created
 * after the cutover. `migrate.mjs`'s builders were written to reproduce the
 * Postgres RLS policy the row was protected by, and Phase 4's gate confirms
 * they do. For the three collections with row security on, those are **not the
 * same set**, and the migration uses the RLS-faithful one:
 *
 *   profiles      RULES: self, admin, techSupport
 *                 here:  self, ward team, admin, ldpCoordinator, projectStaff,
 *                        ewv, ewr                — as `profiles_select` had it
 *   reports       RULES: owner, ward team, ewv, ewr, admin
 *                 here:  + ldpCoordinator, projectStaff, techSupport
 *   verifications RULES: ward team, ewv, ewr, admin
 *                 here:  + the verifier themselves, + ldpCoordinator,
 *                        projectStaff, techSupport
 *
 * Narrowing access during a cutover is not this script's call to make: the
 * migration's one invariant is that every user sees what they saw. So migrated
 * rows match Postgres, and rows created afterwards are narrower — a real
 * inconsistency, pinned by a test in `copy-tables.test.mjs` so that changing
 * either side forces a decision rather than drifting. Whether `RULES` is
 * deliberately narrower (denormalisation removed the need for those reads) or
 * simply missed `ldpCoordinator` and `projectStaff`, who are in `DECIDERS` and
 * must be able to act on a report, is a product question.
 */
export const ACL_SOURCE = {
  profiles: 'migrate.mjs (RLS-faithful)',
  reports: 'migrate.mjs (RLS-faithful)',
  verifications: 'migrate.mjs (RLS-faithful)',
};

/**
 * Every collection, in dependency order, with the Postgres primary key that
 * becomes `$id`.
 *
 * `profiles` before `reports` before `verifications`: a report's ACL names the
 * ward team its author belongs to, and a verification's names the team of the
 * report it votes on, so each needs the one before it read first.
 *
 * `app_settings` is keyed by `key` and not by `id` — and `key` is also a
 * planned column, so it is written as data *and* used as the row id. Nothing
 * here special-cases the key: a column is written when the plan has it, which
 * gets that right without a rule about it.
 */
export const TABLES = [
  {
    table: 'profiles',
    pgId: 'id',
    acl: (row) => profilePermissions(row),
    // `pushTopics` is Appwrite-only and the worker owns it: it records what a
    // device is currently subscribed to, which at migration time is nothing.
  },
  {
    table: 'reports',
    pgId: 'id',
    acl: (row) => reportPermissions(row),
    // Exactly what `RULES.reports.create` stamps, from the author's profile.
    // Appwrite cannot join, and the report list shows who filed it.
    derive: (row, { profiles }) => {
      const author = profiles.get(row.user_id);
      return { userName: author?.name ?? '', userRole: author?.role ?? 'user' };
    },
    // A legacy report with no LGA cannot be addressed to a ward team or validated.
    skip: (row) => (!row.lga ? `report ${row.id} has no LGA` : null),
    // `previousStatus` is deliberately unset: it exists so an event Function
    // can tell a status change from any other edit, and a migrated row has no
    // previous status. Stamping the current one would announce a change that
    // did not happen.
  },
  {
    table: 'verifications',
    pgId: 'id',
    acl: (row, { reports }) => verificationPermissions(row, reports.get(row.report_id)),
    // `stampReportLocation` and `RULES.verifications.create`, which is where
    // the ward team in the ACL above comes from.
    derive: (row, { reports, profiles }) => {
      const report = reports.get(row.report_id);
      const verifier = profiles.get(row.verifier_id);
      return {
        verifierName: verifier?.name ?? '',
        state: report.state,
        lga: report.lga,
        ward: report.ward,
      };
    },
    // A vote on a report that did not migrate has no ward to be read by, and
    // its ACL would name a team derived from nothing.
    skip: (row, { reports }) =>
      reports.has(row.report_id) ? null : `report ${row.report_id} was not migrated`,
  },
  { table: 'alerts', pgId: 'id' },
  { table: 'authorities', pgId: 'id' },
  { table: 'app_settings', pgId: 'key' },
  { table: 'scheduled_escalations', pgId: 'id' },
  { table: 'knowledge_base', pgId: 'id' },
  { table: 'news_links', pgId: 'id' },
  {
    table: 'trusted_devices',
    pgId: 'id',
    acl: (row) => [`read("user:${row.user_id}")`],
  },
  {
    table: 'login_history',
    pgId: 'id',
    acl: (row) => [`read("user:${row.user_id}")`, 'read("label:admin")'],
  },
  {
    table: 'contacts',
    pgId: 'id',
    acl: (row) => [`read("user:${row.user_id}")`, 'read("label:admin")'],
  },
  {
    table: 'messages',
    pgId: 'id',
    acl: () => ['read("label:approved")'],
  },
  {
    table: 'ndpa_consents',
    pgId: 'user_id',
    acl: (row) => [`read("user:${row.user_id}")`, 'read("label:admin")'],
  },
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

/**
 * The row's permissions: the table's own builder where it has one, else what
 * the `client` Function would stamp, else none at all.
 */
export function aclFor(target, row, rowId, context) {
  if (typeof target.acl === 'function') return target.acl(row, context);
  const rule = RULES[target.table];
  if (typeof rule?.acl !== 'function') return null;
  return rule.acl({ documentId: rowId });
}

/**
 * Builds the row body for one Postgres row, or explains why it cannot.
 *
 * Separated from the writing so the mapping can be checked without a server,
 * and so a whole table can be validated before anything is sent.
 */
export function buildRow(row, target, context = {}) {
  const { table, pgId } = target;
  const planned = new Map((COLUMNS[table] ?? []).map((c) => [c.key, c]));
  if (!planned.size) return { error: `no columns planned for ${table}` };

  const skipped = target.skip?.(row, context);
  if (skipped) return { skip: skipped };

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

  // Appwrite-only columns, from the same expressions `write.js` uses. Written
  // after the Postgres ones so a derived value wins where both exist.
  for (const [key, value] of Object.entries(target.derive?.(row, context) ?? {})) {
    const column = planned.get(key);
    if (!column) return { error: `derived ${key} has no planned column` };
    try {
      const v = coerce(value, column);
      if (v !== null) data[key] = v;
    } catch (e) {
      return { error: `${key}: ${e.message}` };
    }
  }

  const missing = [...planned.values()]
    .filter((c) => c.required && data[c.key] === undefined)
    .map((c) => c.key);
  if (missing.length) return { error: `required column(s) unset: ${missing.join(', ')}` };

  return { rowId, data, permissions: aclFor(target, row, rowId, context), unplanned };
}

export async function run({ log = console.log } = {}) {
  const { aw } = appwriteTarget();
  const client = new pg.Client({ connectionString: PG });
  await client.connect();

  const counts = {};
  const failures = [];
  const unplannedColumns = {};

  // Read once, for the ACLs and the denormalised columns: a report's ACL names
  // its author's ward team, a verification's names the report's.
  const context = { profiles: new Map(), reports: new Map() };
  for (const [key, table, idCol] of [
    ['profiles', 'profiles', 'id'],
    ['reports', 'reports', 'id'],
  ]) {
    for (const row of (await client.query(`select * from public.${table}`)).rows) {
      context[key].set(row[idCol], row);
    }
  }

  for (const target of TABLES) {
    const { table, pgId } = target;
    const { rows } = await client.query(`select * from public.${table} order by ${pgId}`);
    const stat = { source: rows.length, created: 0, exists: 0, failed: 0, skipped: 0 };
    counts[table] = stat;

    for (const row of rows) {
      const built = buildRow(row, target, context);
      if (built.skip) {
        stat.skipped += 1;
        failures.push({ table, id: String(row[pgId]), skipped: built.skip });
        continue;
      }
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
        `${stat.exists} already there, ${stat.failed} failed` +
        (stat.skipped ? `, ${stat.skipped} skipped` : ''),
    );
  }

  await client.end();
  return { counts, failures, unplannedColumns };
}

if (process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1])) {
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
  const errors = failures.filter((f) => f.error);
  const skips = failures.filter((f) => f.skipped);
  if (skips.length) {
    console.error(`\n${skips.length} row(s) skipped:`);
    console.error(JSON.stringify(skips.slice(0, 20), null, 2));
  }
  if (errors.length) {
    console.error(`\n${errors.length} row(s) failed:`);
    console.error(JSON.stringify(errors.slice(0, 20), null, 2));
    process.exitCode = 1;
  }
}
