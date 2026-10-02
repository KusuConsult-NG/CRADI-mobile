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

/** Postgres type -> Appwrite column type. */
export function toAppwrite(pgType, name) {
  const t = pgType.toLowerCase();
  if (/^(boolean|bool)\b/.test(t)) return { type: 'boolean' };
  if (/^(timestamptz|timestamp|date)\b/.test(t)) return { type: 'datetime' };
  if (/^(double precision|numeric|real|float)/.test(t)) return { type: 'double' };
  if (/^(int|integer|bigint|smallint)\b/.test(t)) return { type: 'integer' };
  // jsonb has no Appwrite counterpart; it is stored as text and parsed by
  // whoever wrote it. Only `app_settings.value` and the outbox payload use
  // it, and both are already read as opaque.
  if (/^jsonb?\b/.test(t)) return { type: 'string', size: 65535 };
  if (/^uuid\b/.test(t)) return { type: 'string', size: 36 };
  // An unsized `text` could be anything. 8k is generous for every field
  // this app stores except a description or a URL list, which get more.
  const big = /description|content|message|comment|reason|image_urls|urls|payload/.test(name);
  return { type: 'string', size: big ? 65535 : 8192 };
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
      const m = /^(\w+)\s+([a-z0-9_ ]+(?:\([^)]*\))?)/i.exec(line);
      if (!m) continue;
      tables[name][m[1]] = m[2].trim();
    }
  }
  const added = sql.matchAll(
    /alter table (?:public\.)?(\w+)\s+add column (?:if not exists )?(\w+)\s+([a-z0-9_ ]+(?:\([^)]*\))?)/gi,
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
