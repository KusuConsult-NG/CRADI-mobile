import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';

import { COLLECTIONS, FUNCTIONS, clientWritable } from '../../../infra/appwrite/plan.mjs';
import { buildColumns, extract } from '../../../infra/appwrite/extract-schema.mjs';
import { WRITABLE } from '../src/lib/policy.js';

const here = dirname(fileURLToPath(import.meta.url));
const repo = resolve(here, '../../..');

describe('the provisioning plan', () => {
  it('derives its columns from the migrations, and has not drifted', () => {
    // columns.json is generated. A column added to the database and not
    // regenerated here means a write the server rejects — in production,
    // with the report already typed in.
    const dir = join(repo, 'supabase/migrations');
    const sql = readdirSync(dir)
      .filter((f) => f.endsWith('.sql'))
      .sort()
      .map((f) => readFileSync(join(dir, f), 'utf8'))
      .join('\n');

    const fresh = buildColumns(extract(sql));
    const committed = JSON.parse(
      readFileSync(join(repo, 'infra/appwrite/columns.json'), 'utf8'),
    );
    assert.deepEqual(
      committed,
      fresh,
      'Stale. Run: node infra/appwrite/extract-schema.mjs > infra/appwrite/columns.json',
    );
  });

  it('covers the 19 collections Phase 1 kept, and neither dropped table', () => {
    const ids = COLLECTIONS.map((c) => c.id);
    assert.equal(ids.length, 19);
    // Static reference data that already ships in the app; keeping them
    // would buy nothing but a round trip.
    assert.ok(!ids.includes('nigeria_states'));
    assert.ok(!ids.includes('nigeria_lgas'));
    // Rebuilt rather than migrated, but it still has to exist.
    assert.ok(ids.includes('notification_outbox'));
  });

  it('agrees with the write Function about who writes what', () => {
    // Two sets of rules for one collection is how a rule gets enforced
    // in one place and not the other.
    for (const id of clientWritable()) {
      assert.ok(!WRITABLE.has(id), `${id} is client-writable and Function-written`);
    }
    for (const c of COLLECTIONS) {
      if (WRITABLE.has(c.id)) {
        assert.ok(!c.clientWrite, `${c.id} cannot be both`);
      }
    }
  });

  it('agrees with the app about which collections it may write', () => {
    const dart = readFileSync(
      join(repo, 'lib/core/services/appwrite/appwrite_config.dart'),
      'utf8',
    );
    const block = dart.split('clientWritableCollections = {')[1].split('};')[0];
    const names = [...block.matchAll(/AppConfig\.(\w+)/g)].map((m) => m[1]);
    const map = {
      contactsCollection: 'contacts',
      messagesCollection: 'messages',
      trustedDevicesCollection: 'trusted_devices',
      loginHistoryCollection: 'login_history',
      ndpaConsentsCollection: 'ndpa_consents',
    };
    assert.deepEqual(
      names.map((n) => map[n]).sort(),
      clientWritable().sort(),
    );
  });

  it('gives every column the write path depends on a home', () => {
    // The denormalised fields and `previousStatus` are set by the write
    // Function; without a column they are silently dropped, and the
    // event Function then never sees a status change.
    const reports = COLLECTIONS.find((c) => c.id === 'reports').columns.map((c) => c.key);
    for (const key of ['userName', 'userRole', 'previousStatus', 'status', 'escalated']) {
      assert.ok(reports.includes(key), `reports.${key}`);
    }
    const votes = COLLECTIONS.find((c) => c.id === 'verifications').columns.map((c) => c.key);
    for (const key of ['verifierName', 'state', 'lga', 'ward', 'reportId']) {
      assert.ok(votes.includes(key), `verifications.${key}`);
    }
    const outbox = COLLECTIONS.find((c) => c.id === 'notification_outbox').columns.map((c) => c.key);
    for (const key of ['eventType', 'payload', 'attempts', 'availableAt', 'processedAt', 'note']) {
      assert.ok(outbox.includes(key), `notification_outbox.${key}`);
    }
  });

  it('indexes what the worker actually queries', () => {
    const index = (collection, key) =>
      COLLECTIONS.find((c) => c.id === collection).indexes.find((i) => i.key === key);
    // The drain's claim query, run every minute forever.
    assert.ok(index('notification_outbox', 'by_due'));
    assert.ok(index('scheduled_escalations', 'by_status_due'));
    // The SMS daily cap, keyed by (lga, state) because LGA names repeat.
    assert.ok(index('sms_deliveries', 'by_area_day'));
  });

  it('declares every Function the repo actually has an entrypoint for', () => {
    for (const f of FUNCTIONS) {
      const path = join(repo, 'functions/cradi', f.entrypoint);
      assert.doesNotThrow(() => readFileSync(path), `${f.id}: ${f.entrypoint}`);
    }
  });

  it('fits in the two Functions the Cloud plan allows', () => {
    // Not a style rule: the first Cloud run created two and was refused
    // the third (`docs/CLOUD-VERIFICATION.md`). A Function added here
    // would provision cleanly against the local stack and fail on
    // Cloud, which is the expensive way to find out.
    assert.deepEqual(
      FUNCTIONS.map((f) => f.id).sort(),
      ['client', 'worker'],
    );
  });

  it('runs the worker on a schedule, and the client on none', () => {
    const scheduled = FUNCTIONS.filter((f) => f.schedule).map((f) => f.id);
    assert.deepEqual(scheduled, ['worker']);
    // Every minute: `worker.js` folds the drain's and escalation's
    // one-minute cadence and the sweep's five-minute one into this
    // single schedule, and decides the sweep from the clock.
    assert.equal(FUNCTIONS.find((f) => f.id === 'worker').schedule, '* * * * *');
    assert.equal(FUNCTIONS.find((f) => f.id === 'client').schedule, undefined);
  });

  it('subscribes the worker to the five events on-write handled', () => {
    // Events are at-most-once, which is why the sweep exists — the
    // schedule above must never be dropped on the grounds that these
    // cover it.
    const worker = FUNCTIONS.find((f) => f.id === 'worker');
    assert.equal(worker.events.length, 5);
    for (const event of worker.events) {
      assert.match(event, /^databases\.[^.]+\.tables\.[a-z_]+\.rows\.\*\.(create|update)$/);
    }
    assert.deepEqual(FUNCTIONS.find((f) => f.id === 'client').events, undefined);
  });

  it('opens only the client Function to callers, and the worker to none', () => {
    // `client` is `any` because registration and recovery happen before
    // there is a session, and `/auth` lives in it. Its other two routes
    // call `callerId()` first, so a guest still gets a 401 — from the
    // handler rather than from the platform; `client.test.mjs` holds
    // that to it.
    assert.deepEqual(FUNCTIONS.find((f) => f.id === 'client').execute, ['any']);
    // The worker is reached by a schedule and by events, never by a
    // client: an open one would let anybody run the drain.
    assert.deepEqual(FUNCTIONS.find((f) => f.id === 'worker').execute, []);
  });
});
