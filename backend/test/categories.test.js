import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHandlers, runOutboxBatch } from '../src/outbox.js';
import { createAuthoritySms } from '../src/sms/authorities.js';
import { fakePush, fakeRepo, fakeSms, logger, profile } from './helpers.js';

// Every hazard category the app offers (lib/core/constants/hazards.dart).
const CATEGORIES = [
  'Flooding', 'Extreme Temperatures', 'Drought', 'Windstorms', 'Wildfires',
  'Erosion', 'Pest Outbreak', 'Crop Disease', 'Conflict',
];

for (const [i, hazard] of CATEGORIES.entries()) {
  test(`category ${hazard}: verification request, reporter update, broadcast and authority SMS`, async () => {
    const id = `r${i}`;
    const repo = fakeRepo({
      reports: [{ id, user_id: 'reporter', ward: 'W1', lga: 'Makurdi', state: 'Benue', hazard_type: hazard, severity: 'high', status: 'pending', description: 'x' }],
      profiles: [profile('peer', 'ewm', { lga: 'Makurdi', ward: 'W1' })],
      authorities: [{ id: 'a1', phone: '08030000001', coverage_lga: 'Makurdi' }],
      events: [
        { id: 1, event_type: 'report_created', payload: { report_id: id } },
        { id: 2, event_type: 'report_status_changed', payload: { report_id: id, old_status: 'verified', new_status: 'approved' } },
      ],
    });
    const push = fakePush();
    const sms = fakeSms();
    const handlers = createHandlers({ repo, push, logger, authoritySms: createAuthoritySms({ repo, sms, logger }) });

    await runOutboxBatch({ repo, handlers, logger, limit: 1 });
    assert.deepEqual(push.calls[0].ids, ['peer']);
    assert.equal(push.calls[0].n.data.type, 'verification_request');

    repo.state.reports[0].status = 'approved';
    await runOutboxBatch({ repo, handlers, logger });
    assert.ok(repo.state.events.every((e) => e.processed_at), 'all events processed');
    assert.deepEqual(push.calls[1].ids, ['reporter']);
    assert.equal(push.calls[2].kind, 'tag');
    assert.equal(push.calls[2].tagValue, 'makurdi');
    assert.equal(sms.sent.length, 1);
    assert.match(sms.sent[0].text, new RegExp(`HIGH ${hazard} reported in W1, Makurdi`));
  });
}
