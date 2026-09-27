// src/nigeria-lgas.js is generated from the app's canonical location data.
// These tests fail if the two ever drift apart — regenerate with
// `node scripts/gen-nigeria-lgas.mjs`.
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { NIGERIA_LGAS_BY_STATE } from '../src/nigeria-lgas.js';
import { NIGERIAN_STATES } from '../src/transform.js';
import { parseDart, render, DART_PATH } from '../scripts/gen-nigeria-lgas.mjs';

const GENERATED = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)), '../src/nigeria-lgas.js',
);

describe('nigeria-lgas.js is in step with nigeria_locations_data.dart', () => {
  test('the generated file is exactly what the generator would write today', () => {
    const expected = render(parseDart(fs.readFileSync(DART_PATH, 'utf8')));
    assert.equal(
      fs.readFileSync(GENERATED, 'utf8'), expected,
      'src/nigeria-lgas.js is stale — run: node scripts/gen-nigeria-lgas.mjs',
    );
  });

  test('36 states + FCT, 770 LGAs, no duplicates within a state', () => {
    const states = Object.keys(NIGERIA_LGAS_BY_STATE);
    assert.equal(states.length, 37);
    assert.ok(states.includes('FCT'));
    assert.equal(Object.values(NIGERIA_LGAS_BY_STATE).flat().length, 770);
    for (const [state, lgas] of Object.entries(NIGERIA_LGAS_BY_STATE)) {
      assert.equal(new Set(lgas.map((l) => l.toLowerCase())).size, lgas.length, `duplicate LGA in ${state}`);
      for (const lga of lgas) assert.equal(lga, lga.trim(), `padded LGA name ${JSON.stringify(lga)} in ${state}`);
    }
  });

  test('transform.js canonical states come from the same data', () => {
    assert.deepEqual(NIGERIAN_STATES, Object.keys(NIGERIA_LGAS_BY_STATE));
  });
});
