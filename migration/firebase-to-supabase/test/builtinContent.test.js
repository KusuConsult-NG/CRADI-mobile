import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { BUILTIN_GUIDE_TITLES, builtinGuideFor, normalizeTitle } from '../src/builtinContent.js';
import { transformKnowledge } from '../src/transform.js';

const SEED_SQL = path.resolve(path.dirname(fileURLToPath(import.meta.url)),
  '../../../supabase/migrations/20260927040000_builtin_content.sql');
const ctx = { now: '2026-09-25T00:00:00.000Z', user: () => null, report: () => null, url: (u) => u };

/** Titles of the knowledge_base rows the seed migration inserts. */
function seededTitles(sql) {
  const start = sql.indexOf('insert into public.knowledge_base');
  assert.ok(start >= 0, 'knowledge_base insert not found in the seed migration');
  const end = sql.indexOf(';\n', start);
  const block = sql.slice(start, end === -1 ? undefined : end);
  // Each row starts: ('<uuid>', '<title>', $seed$…
  const re = /\(\s*'[0-9a-f-]{36}'\s*,\s*'((?:[^']|'')*)'\s*,\s*\$seed\$/g;
  return [...block.matchAll(re)].map((m) => m[1].replace(/''/g, "'"));
}

test('BUILTIN_GUIDE_TITLES matches the titles seeded by 20260927040000_builtin_content.sql', () => {
  const titles = seededTitles(fs.readFileSync(SEED_SQL, 'utf8'));
  assert.equal(titles.length, 10);
  assert.deepEqual([...titles].sort(), [...BUILTIN_GUIDE_TITLES].sort());
});

test('title matching ignores case, whitespace, punctuation and legacy HTML escaping', () => {
  assert.equal(normalizeTitle('  Bush Fire &  Urban-Fire Response. '), normalizeTitle('bush fire and urban fire response'));
  assert.equal(builtinGuideFor('RIVER BENUE FLOODING PROTOCOLS'), 'River Benue Flooding Protocols');
  assert.equal(builtinGuideFor('Gully erosion mitigation - Nasarawa / Plateau context'), 'Gully Erosion Mitigation (Nasarawa/Plateau Context)');
  assert.equal(builtinGuideFor('Storm &amp; Severe Weather Safety'), 'Storm & Severe Weather Safety');
  assert.equal(builtinGuideFor('River Benue Flooding'), null);
  assert.equal(builtinGuideFor(''), null);
  assert.equal(builtinGuideFor(undefined), null);
});

test('knowledge_base docs duplicating a seeded guide are skipped', () => {
  const dup = transformKnowledge('k1', { title: 'earthquake preparedness and response', content: 'old copy' }, ctx);
  assert.equal(dup.row, undefined);
  assert.match(dup.skip, /replaced by built-in guide 'Earthquake Preparedness & Response'/);
  const own = transformKnowledge('k2', { title: 'Community Flood Drill 2025', content: 'c' }, ctx);
  assert.equal(own.skip, null);
  assert.equal(own.row.title, 'Community Flood Drill 2025');
});
