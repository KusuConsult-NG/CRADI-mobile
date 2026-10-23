#!/usr/bin/env node
/**
 * Re-derives the stored read permissions on existing reports, and the
 * labels on existing accounts, after a change to who may read what.
 *
 *   APPWRITE_ENDPOINT=https://<region>.cloud.appwrite.io/v1 \
 *   APPWRITE_PROJECT_ID=... APPWRITE_API_KEY=... \
 *   node infra/appwrite/fix-report-permissions.mjs [--apply] [--only=reports,labels]
 *
 * **Why this script has to exist.** An Appwrite ACL is not a rule that is
 * evaluated on read; it is a list stored on the row and written once, when
 * the row is created. Changing `RULES.reports.acl` therefore changes
 * nothing about a report that already exists — it governs the next one.
 * So the three read scopes matrix 4.1 asks for would be true of reports
 * filed after the Function is deployed and false of every report filed
 * before it, which is the whole backlog the roles were given access for.
 *
 * Account labels have the same shape of problem from the other direction:
 * `syncLabels` re-derives them on any profile write that touches a field
 * they depend on, so an account is correct from its next edit onward and
 * not before. An LDP Coordinator nobody edits again never gets the LGA
 * label at all.
 *
 * **It is a dry run unless you pass `--apply`.** Rewriting permissions on
 * live rows is not something to do by running a file to see what it does.
 *
 * **It is idempotent and resumable.** Every row is compared before it is
 * written and skipped when it already agrees, so a run that dies halfway
 * is finished by running it again, and a run against an already-correct
 * project writes nothing.
 *
 * **It never widens a scope by accident**, because it does not contain a
 * scope: the lists come from `reportAcl` and `accountLabels`, the same
 * two functions the running Function uses. If those are wrong this is
 * wrong in exactly the same way, which is the point — there is one
 * definition of who may read a report.
 */
import { accountLabels, reportAcl } from '../../functions/cradi/src/lib/policy.js';

const ENDPOINT = process.env.APPWRITE_ENDPOINT ?? process.env.APPWRITE_FUNCTION_API_ENDPOINT;
const PROJECT = process.env.APPWRITE_PROJECT_ID ?? process.env.APPWRITE_PROJECT;
const KEY = process.env.APPWRITE_API_KEY;
const DATABASE = process.env.APPWRITE_DATABASE_ID ?? 'cradi';

const args = process.argv.slice(2);
const APPLY = args.includes('--apply');
const only = args.find((a) => a.startsWith('--only='))?.slice('--only='.length);
const PARTS = new Set(only ? only.split(',').map((s) => s.trim()) : ['reports', 'labels']);
const PAGE = 100;

if (!ENDPOINT || !PROJECT || !KEY) {
  console.error(
    'error: APPWRITE_ENDPOINT, APPWRITE_PROJECT_ID and APPWRITE_API_KEY must be set.\n' +
      '  Keep the key out of your shell history — read it from a file:\n' +
      '    set -a; . ~/.cradi/appwrite-cloud.env; set +a',
  );
  process.exit(2);
}

async function api(path, { method = 'GET', body } = {}) {
  const response = await fetch(`${ENDPOINT}${path}`, {
    method,
    headers: {
      'content-type': 'application/json',
      'x-appwrite-project': PROJECT,
      'x-appwrite-key': KEY,
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  const text = await response.text();
  let parsed = null;
  if (text) {
    try { parsed = JSON.parse(text); } catch { parsed = { message: text }; }
  }
  return { status: response.status, ok: response.ok, body: parsed };
}

const rowsPath = (table) =>
  `/tablesdb/${encodeURIComponent(DATABASE)}/tables/${encodeURIComponent(table)}/rows`;

/**
 * Every row of [table], a page at a time, by cursor.
 *
 * Cursor paging and not offset paging: this rewrites rows as it reads
 * them, and an offset into a table being written underneath you skips
 * rows. A cursor is anchored to the last row seen, so it does not.
 */
async function* allRows(table) {
  let cursor = null;
  for (;;) {
    const queries = [
      JSON.stringify({ method: 'limit', values: [PAGE] }),
      JSON.stringify({ method: 'orderAsc', attribute: '$id' }),
      ...(cursor ? [JSON.stringify({ method: 'cursorAfter', values: [cursor] })] : []),
    ];
    const query = queries.map((q) => `queries[]=${encodeURIComponent(q)}`).join('&');
    const page = await api(`${rowsPath(table)}?${query}`);
    if (!page.ok) throw new Error(`read ${table}: ${page.status} ${page.body?.message ?? ''}`);
    const rows = page.body?.rows ?? [];
    if (rows.length === 0) return;
    for (const row of rows) yield row;
    if (rows.length < PAGE) return;
    cursor = rows[rows.length - 1].$id;
  }
}

/** Order-insensitive, because Appwrite's list is a set and a re-ordering is not a change. */
const same = (a, b) =>
  a.length === b.length && [...a].sort().join('\u0000') === [...b].sort().join('\u0000');

const tally = { checked: 0, changed: 0, skipped: 0, failed: 0 };
const failures = [];

async function fixReports() {
  console.log('\n# reports — stored read permissions');
  for await (const row of allRows('reports')) {
    tally.checked += 1;
    const wanted = reportAcl({ data: row });
    const current = row.$permissions ?? [];
    if (same(wanted, current)) {
      tally.skipped += 1;
      continue;
    }
    if (!APPLY) {
      tally.changed += 1;
      const added = wanted.filter((p) => !current.includes(p));
      const removed = current.filter((p) => !wanted.includes(p));
      console.log(
        `  would rewrite ${row.$id} (${row.status ?? 'no status'})` +
          `${added.length ? ` +${added.join(' +')}` : ''}` +
          `${removed.length ? ` -${removed.join(' -')}` : ''}`,
      );
      continue;
    }
    // `data: {}` — the columns are not being touched, only the ACL. A
    // patch that re-sent the row would race anybody editing it.
    const written = await api(`${rowsPath('reports')}/${encodeURIComponent(row.$id)}`, {
      method: 'PATCH',
      body: { data: {}, permissions: wanted },
    });
    if (written.ok) {
      tally.changed += 1;
      console.log(`  rewrote ${row.$id} (${row.status ?? 'no status'})`);
    } else {
      tally.failed += 1;
      failures.push(`reports/${row.$id}: ${written.status} ${written.body?.message ?? ''}`);
    }
  }
}

async function fixLabels() {
  console.log('\n# accounts — labels derived from the profile');
  for await (const row of allRows('profiles')) {
    tally.checked += 1;
    const wanted = accountLabels(row);
    const account = await api(`/users/${encodeURIComponent(row.$id)}`);
    if (!account.ok) {
      // A profile with no account behind it. Reported rather than
      // counted as a failure: the migration left some, and there is
      // nothing to label.
      tally.skipped += 1;
      console.log(`  no account for profile ${row.$id} (${account.status}) — skipped`);
      continue;
    }
    if (same(wanted, account.body?.labels ?? [])) {
      tally.skipped += 1;
      continue;
    }
    const before = (account.body?.labels ?? []).join(', ') || 'none';
    if (!APPLY) {
      tally.changed += 1;
      console.log(`  would relabel ${row.$id} (${row.role}): [${before}] -> [${wanted.join(', ')}]`);
      continue;
    }
    const written = await api(`/users/${encodeURIComponent(row.$id)}/labels`, {
      method: 'PUT',
      body: { labels: wanted },
    });
    if (written.ok) {
      tally.changed += 1;
      console.log(`  relabelled ${row.$id} (${row.role}): [${before}] -> [${wanted.join(', ')}]`);
    } else {
      tally.failed += 1;
      failures.push(`users/${row.$id}: ${written.status} ${written.body?.message ?? ''}`);
    }
  }
}

console.log(APPLY ? '# applying' : '# dry run — pass --apply to write');
console.log(`# ${ENDPOINT}  project ${PROJECT}  database ${DATABASE}`);

try {
  if (PARTS.has('reports')) await fixReports();
  if (PARTS.has('labels')) await fixLabels();
} catch (error) {
  console.error(`\nerror: ${error.message}`);
  console.error('  Nothing is lost — this script is idempotent. Fix the cause and run it again.');
  process.exit(1);
}

console.log(
  `\n# ${tally.checked} checked, ${tally.changed} ${APPLY ? 'changed' : 'to change'},` +
    ` ${tally.skipped} already correct, ${tally.failed} failed`,
);
for (const line of failures) console.error(`  failed: ${line}`);
// A partial run must not look like a clean one to whatever called it.
process.exit(tally.failed > 0 ? 1 : 0);
