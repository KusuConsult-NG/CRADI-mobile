import { test } from 'node:test';
import assert from 'node:assert/strict';
import { sanitizeTag } from '../src/tags.js';

test('sanitizeTag lowercases and replaces non [a-z0-9_] with _', () => {
  assert.equal(sanitizeTag('Port Harcourt'), 'port_harcourt');
  assert.equal(sanitizeTag('Obio/Akpor'), 'obio_akpor');
  assert.equal(sanitizeTag('Ward_12'), 'ward_12');
  assert.equal(sanitizeTag('Ìbàdàn North-East'), '_b_d_n_north_east');
  assert.equal(sanitizeTag(' Ikeja '), '_ikeja_'); // no trimming, by contract
  assert.equal(sanitizeTag('A  B'), 'a__b'); // no collapsing
});

test('sanitizeTag handles null/undefined/numbers', () => {
  assert.equal(sanitizeTag(null), '');
  assert.equal(sanitizeTag(undefined), '');
  assert.equal(sanitizeTag(42), '42');
});
