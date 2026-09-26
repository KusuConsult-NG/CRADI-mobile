import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHandlers, runOutboxBatch } from '../src/outbox.js';
import { fakePush, fakeRepo, logger, profile } from './helpers.js';

function run(profiles, extra = {}) {
  const repo = fakeRepo({
    profiles,
    events: [{ id: 1, event_type: 'user_access_changed', payload: { user_id: 'u1' } }],
  });
  Object.assign(repo.state, extra);
  const handlers = createHandlers({ repo, push: fakePush(), logger });
  return { repo, done: runOutboxBatch({ repo, handlers, logger }) };
}

test('user_access_changed bans a disabled user and unbans an enabled one', async () => {
  const blocked = run([profile('u1', 'ewm', { is_disabled: true })]);
  await blocked.done;
  assert.equal(blocked.repo.state.bans.u1, true);
  assert.equal(blocked.repo.state.events[0].processed_at, 'now');

  const unblocked = run([profile('u1', 'ewm', { is_disabled: false })]);
  await unblocked.done;
  assert.equal(unblocked.repo.state.bans.u1, false);
});

test('user_access_changed for a deleted user is processed without error', async () => {
  const gone = run([]);
  await gone.done;
  assert.equal(gone.repo.state.events[0].processed_at, 'now');
  assert.equal(gone.repo.state.bans, undefined);

  const noAuth = run([profile('u1', 'ewm', { is_disabled: true })], { missingAuthUsers: ['u1'] });
  await noAuth.done;
  assert.equal(noAuth.repo.state.events[0].processed_at, 'now');
});
