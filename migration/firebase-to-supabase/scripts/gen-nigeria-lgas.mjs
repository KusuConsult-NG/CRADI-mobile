#!/usr/bin/env node
// Regenerates src/nigeria-lgas.js from the app's canonical location data:
//
//   node scripts/gen-nigeria-lgas.mjs
//
// The Dart file (lib/core/data/nigeria_locations_data.dart) is the single
// source of truth for state and LGA spellings — the same data the admin
// pickers and supabase/migrations/20260927080000 are built from. Run this
// after changing it; test/nigeria-lgas.test.js fails if the two drift apart.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const DART_PATH = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '../../../lib/core/data/nigeria_locations_data.dart',
);

/** Parse `NigeriaLocation(state: 'X', lgas: [...])` entries into { state: [lga, ...] }. */
export function parseDart(source) {
  const entry = /state:\s*'((?:[^'\\]|\\.)*)'\s*,\s*lgas:\s*\[([\s\S]*?)\]\s*,\s*\)/g;
  const unquote = (s) => s.replace(/\\'/g, "'").replace(/\\\\/g, '\\');
  const out = {};
  for (const m of source.matchAll(entry)) {
    out[unquote(m[1])] = [...m[2].matchAll(/'((?:[^'\\]|\\.)*)'/g)].map((x) => unquote(x[1]));
  }
  return out;
}

export function render(byState) {
  const lit = (s) => `'${s.replace(/\\/g, '\\\\').replace(/'/g, "\\'")}'`;
  const body = Object.entries(byState)
    .map(([state, lgas]) => `  ${lit(state)}: [\n${lgas.map((l) => `    ${lit(l)},`).join('\n')}\n  ],`)
    .join('\n');
  const states = Object.keys(byState).length;
  const lgas = Object.values(byState).reduce((n, l) => n + l.length, 0);
  return `// GENERATED FILE — do not edit by hand.
//
// The ${states - 1} states + FCT (${states} entries) and their ${lgas} LGAs, in the
// canonical spellings the database stores (public.nigeria_states /
// public.nigeria_lgas, seeded by
// supabase/migrations/20260927080000_alert_state_required.sql).
//
// Source of truth: lib/core/data/nigeria_locations_data.dart
// Regenerate:      node scripts/gen-nigeria-lgas.mjs
// Drift guard:     test/nigeria-lgas.test.js re-parses the Dart file and
//                  compares it with this one, so the two cannot diverge.

export const NIGERIA_LGAS_BY_STATE = {
${body}
};
`;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const byState = parseDart(fs.readFileSync(DART_PATH, 'utf8'));
  const out = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../src/nigeria-lgas.js');
  fs.writeFileSync(out, render(byState));
  console.log(`wrote ${out}: ${Object.keys(byState).length} states, ${Object.values(byState).reduce((n, l) => n + l.length, 0)} LGAs`);
}
