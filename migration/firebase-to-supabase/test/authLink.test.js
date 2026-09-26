import { test } from 'node:test';
import assert from 'node:assert/strict';

import { MIGRATION_MARKER, migrationAppMetadata, migrationStart, reuseRefusal } from '../src/authLink.js';

const start = '2026-09-20T10:00:00.000Z';
const before = '2026-09-01T00:00:00.000Z';
const after = '2026-09-20T10:05:00.000Z';

test('reuse: confirmed email account created before the migration', () => {
  assert.equal(reuseRefusal({ id: 'u', email_confirmed_at: before, created_at: before }, { kind: 'email', startIso: start }), null);
  assert.equal(reuseRefusal({ id: 'u', phone_confirmed_at: before, created_at: before }, { kind: 'phone', startIso: start }), null);
});

test('refuse: unconfirmed, or confirmed on the wrong identifier', () => {
  assert.match(reuseRefusal({ id: 'u', created_at: before }, { kind: 'email', startIso: start }), /unconfirmed email/);
  assert.match(
    reuseRefusal({ id: 'u', phone_confirmed_at: before, created_at: before }, { kind: 'email', startIso: start }),
    /unconfirmed email/,
  );
});

test('refuse: created at or after the migration start, or unknown creation time', () => {
  assert.match(reuseRefusal({ id: 'u', email_confirmed_at: after, created_at: after }, { kind: 'email', startIso: start }), /not before/);
  assert.match(reuseRefusal({ id: 'u', email_confirmed_at: start, created_at: start }, { kind: 'email', startIso: start }), /not before/);
  assert.match(reuseRefusal({ id: 'u', email_confirmed_at: before }, { kind: 'email', startIso: start }), /not before/);
});

test('reuse: account created by this script (app_metadata marker), even unconfirmed / after start', () => {
  const ours = { id: 'u', created_at: after, app_metadata: migrationAppMetadata('fb1') };
  assert.equal(ours.app_metadata[MIGRATION_MARKER], true);
  assert.equal(reuseRefusal(ours, { kind: 'email', startIso: start }), null);
  // user_metadata is user-editable and is not trusted.
  assert.match(
    reuseRefusal({ id: 'u', created_at: after, user_metadata: { [MIGRATION_MARKER]: true } }, { kind: 'email', startIso: start }),
    /unconfirmed/,
  );
});

test('migrationStart: earliest recorded run, else fallback', () => {
  assert.equal(migrationStart([{ startedAt: after }, { startedAt: start }], after), start);
  assert.equal(migrationStart([], start), start);
  assert.equal(migrationStart([{ startedAt: 'bad' }], start), start);
});
