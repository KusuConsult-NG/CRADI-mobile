/**
 * The storage buckets, and the URLs on the rows that point into them.
 *
 * Phase 4's reconciler said storage was "reported, not compared: no script here
 * migrates it, so there is no Supabase-object-name -> Appwrite-file-id mapping
 * to diff." There is one — the app's — it just was not being used. See
 * `storage-ids.mjs`: the Flutter client derives the id from the path at render
 * time and nothing persists it, so a file stored under any other id is
 * unreachable, and the only symptom is an image that does not load.
 *
 * Two jobs, in this order, because the second needs the first:
 *
 *   1. copy the bytes, under the id the app will ask for
 *   2. rewrite the Supabase URLs still on the migrated rows
 *
 *   PG_URL                     Postgres, for the object list and the rewrite
 *   SUPABASE_URL               https://<ref>.supabase.co — where the bytes are
 *   SUPABASE_SERVICE_ROLE_KEY  optional; only needed for a non-public bucket
 *   AW_ENDPOINT / AW_PROJECT / AW_KEY
 *   STORAGE_MAP                optional path to write the mapping as JSON
 *
 * Idempotent: the id is a function of the path, so a re-run answers 409 and
 * uploads nothing. The rewrite is idempotent because an Appwrite URL no longer
 * matches the Supabase pattern it looks for.
 */
import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import pg from 'pg';
import { appwriteTarget } from './target.mjs';
import { fileIdFor, fileViewUrl, idsFor } from './storage-ids.mjs';

const PG = process.env.PG_URL ?? 'postgres://postgres:postgres@localhost:5432/cradi_mig';
const DB = process.env.APPWRITE_DATABASE_ID ?? 'cradi';
const SUPABASE_URL = (process.env.SUPABASE_URL ?? '').replace(/\/+$/, '');
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY ?? '';

/**
 * The columns that hold a storage URL, and the table they are on.
 *
 * `news_links.url` is deliberately absent: it is a link to someone else's
 * article, not a file of ours, and rewriting it would break it.
 */
export const URL_COLUMNS = [
  { table: 'reports', column: 'imageUrls', array: true },
  { table: 'profiles', column: 'profileImageUrl', array: false },
  { table: 'knowledge_base', column: 'imageUrl', array: false },
];

/** Where a Supabase storage URL points, or null when it is not one. */
export function parseSupabaseObjectUrl(value) {
  const m = /\/storage\/v1\/object\/(?:public\/|authenticated\/|sign\/)?([^/?#]+)\/([^?#]+)/.exec(
    String(value ?? ''),
  );
  if (!m) return null;
  return { bucket: decodeURIComponent(m[1]), name: decodeURIComponent(m[2]) };
}

/** The public download URL for a Supabase object. */
const supabaseObjectUrl = (bucket, name) =>
  `${SUPABASE_URL}/storage/v1/object/${SERVICE_KEY ? '' : 'public/'}` +
  `${encodeURIComponent(bucket)}/${name.split('/').map(encodeURIComponent).join('/')}`;

const FILENAME = (name) => name.split('/').pop() || 'upload';

async function download(bucket, name) {
  const r = await fetch(supabaseObjectUrl(bucket, name), {
    headers: SERVICE_KEY ? { authorization: `Bearer ${SERVICE_KEY}` } : {},
  });
  if (!r.ok) throw new Error(`GET ${bucket}/${name}: ${r.status}`);
  return {
    bytes: new Uint8Array(await r.arrayBuffer()),
    type: r.headers.get('content-type') ?? 'application/octet-stream',
  };
}

/**
 * Uploads one file. Multipart, so it cannot go through `target.mjs`'s `aw`,
 * which sets a JSON content type.
 */
async function upload({ endpoint, project, key }, bucket, fileId, name, file) {
  const form = new FormData();
  form.append('fileId', fileId);
  form.append('file', new Blob([file.bytes], { type: file.type }), FILENAME(name));
  const r = await fetch(`${endpoint}/storage/buckets/${bucket}/files`, {
    method: 'POST',
    headers: { 'x-appwrite-project': project, 'x-appwrite-key': key },
    body: form,
  });
  return { status: r.status, body: await r.json().catch(() => null) };
}

export async function run({ log = console.log } = {}) {
  const target = appwriteTarget();
  const client = new pg.Client({ connectionString: PG });
  await client.connect();

  const objects = (
    await client.query(
      `select bucket_id, name from storage.objects
        where name is not null and name <> '' order by bucket_id, name`,
    )
  ).rows;

  if (objects.length && !SUPABASE_URL) {
    await client.end();
    throw new Error(
      `${objects.length} object(s) to copy but SUPABASE_URL is not set — there is` +
        ' nowhere to read the bytes from.',
    );
  }

  // Every id up front: a collision must stop the run, not be discovered when
  // the second upload silently replaces the first.
  const ids = idsFor(objects.map((o) => o.name));

  const buckets = {};
  const failures = [];
  const mapping = {};

  for (const { bucket_id: bucket, name } of objects) {
    const stat = (buckets[bucket] ??= { source: 0, copied: 0, exists: 0, failed: 0 });
    stat.source += 1;
    const fileId = ids.get(name);
    mapping[`${bucket}/${name}`] = {
      bucket,
      fileId,
      url: fileViewUrl({ ...target, bucketId: bucket, fileId }),
    };
    try {
      const file = await download(bucket, name);
      const r = await upload(target, bucket, fileId, name, file);
      if (r.status === 201) stat.copied += 1;
      else if (r.status === 409) stat.exists += 1;
      else throw new Error(`${r.status} ${String(r.body?.message ?? '').slice(0, 140)}`);
    } catch (e) {
      stat.failed += 1;
      failures.push({ bucket, name, fileId, error: e.message });
    }
  }

  for (const [bucket, s] of Object.entries(buckets)) {
    log(
      `${bucket.padEnd(16)} ${s.source} object(s): ${s.copied} copied, ` +
        `${s.exists} already there, ${s.failed} failed`,
    );
  }

  // ── the URLs still on the rows ────────────────────────────────────────────
  const rewrites = {};
  for (const { table, column, array } of URL_COLUMNS) {
    const stat = (rewrites[table] = {
      rows: 0, changed: 0, values: 0, skipped: 0, absent: 0,
    });
    const list = await target.aw(
      `/tablesdb/${DB}/tables/${table}/rows?` +
        `queries[]=${encodeURIComponent(JSON.stringify({ method: 'limit', values: [1000] }))}`,
    );
    if (!list.body?.rows) {
      stat.skipped = 1;
      continue;
    }
    for (const row of list.body.rows) {
      stat.rows += 1;
      const current = row[column];
      if (current === undefined || current === null) {
        stat.absent += 1;
        continue;
      }
      const before = array ? current : [current];
      let touched = false;
      const after = before.map((v) => {
        const at = parseSupabaseObjectUrl(v);
        if (!at) return v;
        touched = true;
        stat.values += 1;
        return fileViewUrl({ ...target, bucketId: at.bucket, fileId: fileIdFor(at.name) });
      });
      if (!touched) continue;
      const patch = await target.aw(
        `/tablesdb/${DB}/tables/${table}/rows/${encodeURIComponent(row.$id)}`,
        {
          method: 'PATCH',
          body: JSON.stringify({ data: { [column]: array ? after : after[0] } }),
        },
      );
      if (patch.status === 200) stat.changed += 1;
      else {
        failures.push({
          table,
          id: row.$id,
          error: `rewrite ${column}: ${patch.status} ${String(patch.body?.message ?? '').slice(0, 120)}`,
        });
      }
    }
    if (stat.skipped) {
      log(`${table}.${column}: table not migrated yet, nothing to rewrite`);
    } else if (stat.rows === 0) {
      log(`${table}.${column}: no rows yet — copy-tables.mjs runs before this`);
    } else if (stat.absent === stat.rows) {
      // Worth its own line: "0 of 3 rewritten" reads like there was nothing to
      // do, when in fact the column never arrived and every image is lost.
      log(
        `${table}.${column}: column ABSENT on all ${stat.rows} row(s) — whatever` +
          ' migrated this table does not carry it',
      );
    } else {
      log(
        `${table}.${column}: ${stat.changed} of ${stat.rows} row(s) rewritten ` +
          `(${stat.values} URL(s))`,
      );
    }
  }

  await client.end();

  if (process.env.STORAGE_MAP) {
    writeFileSync(process.env.STORAGE_MAP, `${JSON.stringify(mapping, null, 2)}\n`);
    log(`mapping written to ${process.env.STORAGE_MAP}`);
  }
  return { buckets, rewrites, failures, mapping };
}

if (process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1])) {
  const { buckets, rewrites, failures } = await run();
  console.log(JSON.stringify({ buckets, rewrites }, null, 2));
  if (failures.length) {
    console.error(`\n${failures.length} failure(s):`);
    console.error(JSON.stringify(failures.slice(0, 20), null, 2));
    process.exitCode = 1;
  }
}
