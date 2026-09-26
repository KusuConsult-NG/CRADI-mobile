import { test } from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';

import {
  StopRequested, deferred, installStopHandlers, onceAsync, throwIfStopped,
} from '../src/lifecycle.js';

test('onceAsync runs the function once and shares its promise', async () => {
  let calls = 0;
  const finish = onceAsync(async () => { calls += 1; await new Promise((r) => setTimeout(r, 5)); return 'done'; });
  assert.equal(finish.started, false);
  const [a, b] = await Promise.all([finish(), finish()]);
  assert.equal(finish.started, true);
  assert.equal(await finish(), 'done');
  assert.deepEqual([a, b, calls], ['done', 'done', 1]);
});

test('throwIfStopped throws StopRequested only after a signal', () => {
  const stop = { signal: null };
  throwIfStopped(stop);
  stop.signal = 'SIGTERM';
  assert.throws(() => throwIfStopped(stop), (e) => e instanceof StopRequested && e.signal === 'SIGTERM');
});

function harness({ graceMs = 1000 } = {}) {
  const proc = new EventEmitter();
  const stop = { signal: null };
  const unwound = deferred();
  const order = [];
  let finishCalls = 0;
  const finish = onceAsync(async () => { finishCalls += 1; order.push('finish'); });
  const exited = deferred();
  const remove = installStopHandlers({
    stop, finish, unwound: unwound.promise, graceMs, proc,
    exit: (code) => { order.push(`exit ${code}`); exited.resolve(code); },
    log: () => {},
  });
  return { proc, stop, unwound, finish, order, exited, remove, finishCalls: () => finishCalls };
}

test('SIGINT stops the run, waits for the finally block, finishes once, exits 130', async () => {
  const h = harness();
  h.proc.emit('SIGINT', 'SIGINT');
  assert.equal(h.stop.signal, 'SIGINT');
  // The runner notices the stop, unwinds and its finally calls finish too.
  await new Promise((r) => setTimeout(r, 5));
  assert.deepEqual(h.order, [], 'waits for the runner to unwind');
  h.unwound.resolve();
  await h.finish();
  assert.equal(await h.exited.promise, 130);
  assert.equal(h.finishCalls(), 1);
  assert.deepEqual(h.order, ['finish', 'exit 130']);
  h.remove();
});

test('SIGTERM finishes after the grace period even if the runner is stuck; exits 143', async () => {
  const h = harness({ graceMs: 10 });
  h.proc.emit('SIGTERM', 'SIGTERM');
  assert.equal(await h.exited.promise, 143);
  assert.equal(h.finishCalls(), 1);
  h.remove();
});

test('a second signal exits immediately; remove() detaches the handlers', async () => {
  const h = harness();
  h.proc.emit('SIGINT', 'SIGINT');
  h.proc.emit('SIGINT', 'SIGINT');
  assert.equal(await h.exited.promise, 130);
  assert.equal(h.finishCalls(), 0);
  h.unwound.resolve(); // let the first handler complete
  h.remove();
  assert.equal(h.proc.listenerCount('SIGINT'), 0);
  assert.equal(h.proc.listenerCount('SIGTERM'), 0);
});
