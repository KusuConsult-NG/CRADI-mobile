import { test } from 'node:test';
import assert from 'node:assert/strict';

import { selectAll } from '../src/db.js';
import {
  applyPreflight, importedEvents, importedIdSets, suppressionBaseline, suppressSideEffects,
} from '../src/sideEffects.js';

/** Minimal in-memory stand-in for the supabase-js query builder. */
function fakeSupabase(tables) {
  const calls = [];
  return {
    calls,
    tables,
    from(table) {
      const q = { table, filters: [], order: null, range: null, patch: null, select: false };
      const rows = () => tables[table].filter((r) => q.filters.every((f) => f(r)));
      const run = () => {
        calls.push(q);
        if (q.patch) {
          const hit = rows();
          hit.forEach((r) => Object.assign(r, q.patch));
          return { data: hit.map((r) => ({ id: r.id })), error: null };
        }
        let out = rows();
        if (q.order) out = [...out].sort((a, b) => (a[q.order] > b[q.order] ? 1 : -1));
        if (q.range) out = out.slice(q.range[0], q.range[1] + 1);
        return { data: out, error: null };
      };
      const b = {
        select() { q.select = true; return b; },
        update(patch) { q.patch = patch; return b; },
        gt(c, v) { q.filters.push((r) => r[c] > v); return b; },
        eq(c, v) { q.filters.push((r) => r[c] === v); return b; },
        is(c, v) { q.filters.push((r) => (r[c] ?? null) === v); return b; },
        in(c, vs) { q.filters.push((r) => vs.includes(r[c])); return b; },
        order(c) { q.order = c; return b; },
        range(from, to) { q.range = [from, to]; return b; },
        then(resolve, reject) { return Promise.resolve(run()).then(resolve, reject); },
      };
      return b;
    },
  };
}

test('selectAll orders by the primary key and pages until a short page', async () => {
  const rows = Array.from({ length: 2500 }, (_, i) => ({ id: 2500 - i }));
  const sb = fakeSupabase({ t: rows });
  const out = await selectAll(sb, 't', 'id');
  assert.equal(out.length, 2500);
  assert.deepEqual(out.slice(0, 3).map((r) => r.id), [1, 2, 3]);
  assert.equal(sb.calls.length, 3);
  assert.ok(sb.calls.every((c) => c.order === 'id'));
});

test('applyPreflight refuses --apply without --i-stopped-the-backend', () => {
  assert.equal(applyPreflight({ apply: false }), null);
  assert.match(applyPreflight({ apply: true }), /--i-stopped-the-backend/);
  assert.equal(applyPreflight({ apply: true, 'i-stopped-the-backend': true }), null);
});

test('importedEvents keeps only events for imported reports/alerts', () => {
  const rows = [
    { id: 1, payload: { report_id: 'r-imported' } },
    { id: 2, payload: { report_id: 'r-real-user' } },
    { id: 3, payload: { alert_id: 'a-imported' } },
    { id: 4, payload: {} },
    { id: 5, payload: null },
  ];
  const out = importedEvents(rows, { reportIds: new Set(['r-imported']), alertIds: new Set(['a-imported']) });
  assert.deepEqual(out.map((r) => r.id), [1, 3]);
});

test('suppressSideEffects only touches imported rows after the baseline, and is repeatable', async () => {
  const sb = fakeSupabase({
    notification_outbox: [
      { id: 5, payload: { report_id: 'imp' }, processed_at: null }, // before baseline
      { id: 11, payload: { report_id: 'imp' }, processed_at: null },
      { id: 12, payload: { report_id: 'real' }, processed_at: null }, // real user's event during import
      { id: 13, payload: { alert_id: 'alert-imp' }, processed_at: null },
      { id: 14, payload: { report_id: 'imp' }, processed_at: 'done' },
    ],
    scheduled_escalations: [
      { id: 'e1', report_id: 'imp', status: 'pending' },
      { id: 'e2', report_id: 'real', status: 'pending' },
    ],
  });
  const opts = { baseline: 10, reportIds: new Set(['imp']), alertIds: new Set(['alert-imp']) };
  const res = await suppressSideEffects(sb, opts);
  assert.deepEqual(res, { outbox: 2, escalations: 1, errors: [] });

  const byId = Object.fromEntries(sb.tables.notification_outbox.map((r) => [r.id, r]));
  assert.equal(byId[5].processed_at, null);
  assert.ok(byId[11].processed_at);
  assert.equal(byId[11].last_error, 'migration import');
  assert.equal(byId[12].processed_at, null);
  assert.ok(byId[13].processed_at);
  assert.equal(byId[14].processed_at, 'done');
  assert.equal(sb.tables.scheduled_escalations[0].status, 'skipped');
  assert.equal(sb.tables.scheduled_escalations[1].status, 'pending');

  assert.deepEqual(await suppressSideEffects(sb, opts), { outbox: 0, escalations: 0, errors: [] });
  assert.deepEqual(await suppressSideEffects(sb, { ...opts, baseline: null }), { outbox: 0, escalations: 0, errors: [] });
});

test('suppressionBaseline is the lowest baseline recorded by any run', () => {
  const runs = [{ outboxBaseline: 40 }, { outboxBaseline: 12 }, { outboxBaseline: null }, {}, { outboxBaseline: 55 }];
  assert.equal(suppressionBaseline(runs, 60), 12);
  assert.equal(suppressionBaseline([], 7), 7);
  assert.equal(suppressionBaseline([{ outboxBaseline: 0 }], 9), 0);
  assert.equal(suppressionBaseline([], null), null);
  assert.equal(suppressionBaseline(undefined), null);
});

test('importedIdSets covers every id in the state file plus legacy reports', () => {
  const sets = importedIdSets({ ids: { reports: { fa: 'r-a', fb: 'r-b' }, alerts: { x: 'al-x' }, messages: { m: 'msg' } } }, ['r-legacy']);
  assert.deepEqual([...sets.reportIds].sort(), ['r-a', 'r-b', 'r-legacy']);
  assert.deepEqual([...sets.alertIds], ['al-x']);
  const empty = importedIdSets({ ids: {} });
  assert.equal(empty.reportIds.size + empty.alertIds.size, 0);
});

test('a re-run neutralises events a killed earlier run left behind', async () => {
  // Run 1 (baseline 10) imported report r-old and alert al-old, then was
  // killed before its final suppression. Run 2 starts at baseline 20.
  const sb = fakeSupabase({
    notification_outbox: [
      { id: 11, payload: { report_id: 'r-old' }, processed_at: null },
      { id: 12, payload: { alert_id: 'al-old' }, processed_at: null },
      { id: 13, payload: { report_id: 'r-real' }, processed_at: null },
      { id: 21, payload: { report_id: 'r-new' }, processed_at: null },
    ],
    scheduled_escalations: [{ id: 'e1', report_id: 'r-old', status: 'pending' }],
  });
  const state = { ids: { reports: { a: 'r-old', b: 'r-new' }, alerts: { c: 'al-old' } }, runs: [{ outboxBaseline: 10 }, { outboxBaseline: 20 }] };
  const res = await suppressSideEffects(sb, { baseline: suppressionBaseline(state.runs, 20), ...importedIdSets(state) });
  assert.deepEqual(res, { outbox: 3, escalations: 1, errors: [] });
  const byId = Object.fromEntries(sb.tables.notification_outbox.map((r) => [r.id, r]));
  assert.ok(byId[11].processed_at && byId[12].processed_at && byId[21].processed_at);
  assert.equal(byId[13].processed_at, null);
});
