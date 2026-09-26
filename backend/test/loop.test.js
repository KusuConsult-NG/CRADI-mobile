import { test } from 'node:test';
import assert from 'node:assert/strict';
import { withTimeout } from '../src/http.js';
import { loopHealth } from '../src/loop.js';

const at = (iso) => Date.parse(iso);

test('loopHealth: fresh, stale (> 5x interval), failed, never ran', () => {
  const base = { intervalMs: 1000, startedAt: '2026-01-01T00:00:00.000Z', lastSuccessAt: null, lastError: null };
  const ran = { ...base, lastRunAt: '2026-01-01T00:00:10.000Z' };
  assert.equal(loopHealth(ran, at('2026-01-01T00:00:15.000Z')).healthy, true);
  assert.deepEqual(
    { ...loopHealth(ran, at('2026-01-01T00:00:15.001Z')) },
    { lastRunAt: ran.lastRunAt, lastSuccessAt: null, stale: true, healthy: false },
  );
  assert.equal(loopHealth({ ...ran, lastError: 'boom' }, at('2026-01-01T00:00:11.000Z')).healthy, false);
  // Never completed a tick: measured from start.
  assert.equal(loopHealth({ ...base, lastRunAt: null }, at('2026-01-01T00:00:04.000Z')).healthy, true);
  assert.equal(loopHealth({ ...base, lastRunAt: null }, at('2026-01-01T00:00:06.000Z')).stale, true);
});

test('withTimeout aborts a hung request', async () => {
  const hung = (_url, { signal }) =>
    new Promise((_, reject) => signal.addEventListener('abort', () => reject(signal.reason)));
  // AbortSignal.timeout's timer is unref'd; keep the event loop alive meanwhile.
  const keepAlive = setTimeout(() => {}, 1000);
  await assert.rejects(withTimeout(hung, 20)('http://x'), { name: 'TimeoutError' });
  clearTimeout(keepAlive);
  // A caller signal still works alongside the timeout.
  const ac = new AbortController();
  const p = withTimeout(hung, 10_000)('http://x', { signal: ac.signal });
  ac.abort();
  await assert.rejects(p, { name: 'AbortError' });
});
