/**
 * Derives the Appwrite column definitions from the Postgres migrations.
 *
 *   node infra/appwrite/extract-schema.mjs > infra/appwrite/columns.json
 *
 * Hand-writing 19 collections' worth of columns would have been faster
 * and would have been a second source of truth for a schema that already
 * has one. `supabase/migrations/` is what the live database is; this
 * reads it, so a column added there and forgotten here shows up as a
 * diff rather than as a write the server rejects at 3am.
 *
 * `verify.mjs` fails when the committed `columns.json` no longer matches
 * what this produces.
 */
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const DIR = 'supabase/migrations';

/**
 * How long a string column may be.
 *
 * This is not cosmetic, and getting it wrong is how the first real run
 * of the provisioner failed. Appwrite stores a sized string as a
 * MariaDB `VARCHAR`, and **MariaDB caps a whole row at 65,535 bytes** —
 * four bytes per character under utf8mb4. An unsized Postgres `text`
 * mapped to a generous 8192 therefore costs 32KB of the row budget, and
 * four such columns exhaust it:
 *
 *     ! stopped at profiles.email: The maximum number or size of
 *       columns for this table has been reached.
 *
 * Above roughly 16,000 characters Appwrite switches to `TEXT`, which is
 * stored away from the row and costs it almost nothing. So the sizes
 * below are deliberately **small for ordinary fields and large for long
 * ones** — the middle is the expensive place to be.
 *
 * `reports` has 34 columns, which is what makes this tight enough to
 * matter.
 */
export function stringSize(name) {
  // Long prose and lists: big enough to become TEXT, which frees the row.
  if (/description|content|message|comment|reason|image_urls|urls|payload|note|monitoring_zone|location_details/.test(name)) {
    return 65535;
  }
  if (/url|link/.test(name)) return 2048;
  // Enumerations and short codes.
  if (/^(role|status|severity|type|category|action|method|platform|kind|key)$/.test(name)) {
    return 64;
  }
  if (/_id$|^id$|fingerprint/.test(name)) return 64;
  // Names, addresses, places, contact details.
  return 255;
}

/** Postgres type -> Appwrite column type. */
export function toAppwrite(pgType, name) {
  let t = pgType.toLowerCase().trim();
  // `text[]` is a list, and dropping the brackets silently turns it into
  // a scalar. `reports.image_urls` was mapped that way, so every report
  // with a photo was refused with "Attribute \"imageUrls\" has invalid
  // type" — the app's main flow, and nothing in the schema said why.
  const isArray = /\[\]$/.test(t);
  if (isArray) t = t.replace(/\s*\[\]$/, '');
  const mapped = toAppwriteScalar(t, name);
  // Appwrite sizes an array column per element, and stores the whole
  // column away from the row, so a list of URLs wants a URL's size and
  // not a whole row's budget.
  if (isArray) {
    return {
      ...mapped,
      array: true,
      ...(mapped.type === 'string' ? { size: 2048 } : {}),
    };
  }
  return mapped;
}

function toAppwriteScalar(t, name) {
  if (/^(boolean|bool)\b/.test(t)) return { type: 'boolean' };
  if (/^(timestamptz|timestamp|date)\b/.test(t)) return { type: 'datetime' };
  if (/^(double precision|numeric|real|float)/.test(t)) return { type: 'double' };
  if (/^(int|integer|bigint|smallint)\b/.test(t)) return { type: 'integer' };
  // jsonb has no Appwrite counterpart; it is stored as text and parsed
  // by whoever wrote it. Only `app_settings.value` and the outbox
  // payload use it, and both are already read as opaque.
  if (/^jsonb?\b/.test(t)) return { type: 'string', size: 65535 };
  if (/^uuid\b/.test(t)) return { type: 'string', size: 36 };
  // An explicit varchar(n) says what it needs; honour it.
  const sized = /^(?:varchar|character varying)\((\d+)\)/.exec(t);
  if (sized) return { type: 'string', size: Number(sized[1]) };
  return { type: 'string', size: stringSize(name) };
}

const required = (def) => /\bnot null\b/.test(def) && !/\bdefault\b/.test(def);

export function extract(sql) {
  const tables = {};
  const blocks = sql.matchAll(
    /create table (?:if not exists )?(?:public\.)?(\w+)\s*\(([\s\S]*?)\n\);/gi,
  );
  for (const [, name, body] of blocks) {
    tables[name] ??= {};
    for (let line of body.split('\n')) {
      line = line.trim().replace(/,$/, '');
      if (!line || line.startsWith('--')) continue;
      if (/^(primary key|unique|constraint|foreign key|check|exclude)\b/i.test(line)) continue;
      const m = /^(\w+)\s+([a-z0-9_ ]+(?:\([^)]*\))?(?:\s*\[\])?)/i.exec(line);
      if (!m) continue;
      tables[name][m[1]] = m[2].trim();
    }
  }
  const added = sql.matchAll(
    /alter table (?:public\.)?(\w+)\s+add column (?:if not exists )?(\w+)\s+([a-z0-9_ ]+(?:\([^)]*\))?(?:\s*\[\])?)/gi,
  );
  for (const [, table, column, type] of added) {
    tables[table] ??= {};
    tables[table][column] = type.trim();
  }
  const dropped = sql.matchAll(
    /alter table (?:public\.)?(\w+)\s+drop column (?:if exists )?(\w+)/gi,
  );
  for (const [, table, column] of dropped) delete tables[table]?.[column];
  return tables;
}

/** snake_case -> the camelCase the app and the Appwrite collections use. */
export const toField = (column) =>
  column.replace(/_([a-z0-9])/g, (_, c) => c.toUpperCase());

export function buildColumns(tables) {
  const out = {};
  for (const [table, columns] of Object.entries(tables)) {
    out[table] = Object.entries(columns)
      .filter(([name]) => name !== 'id') // Appwrite's $id
      .map(([name, def]) => ({
        key: toField(name),
        ...toAppwrite(def, name),
        required: required(def),
      }))
      .sort((a, b) => a.key.localeCompare(b.key));
  }
  return out;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const sql = readdirSync(DIR)
    .filter((f) => f.endsWith('.sql'))
    .sort()
    .map((f) => readFileSync(join(DIR, f), 'utf8'))
    .join('\n');
  process.stdout.write(`${JSON.stringify(buildColumns(extract(sql)), null, 2)}\n`);
}
