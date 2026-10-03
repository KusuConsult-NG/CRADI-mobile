import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import worker, { RECONCILE_EVERY_MINUTES, isSweepMinute, tasksFor } from '../src/worker.js';
import { runDrain } from '../src/drain.js';
import { runEscalate } from '../src/escalate.js';
import { runReconcile } from '../src/reconcile.js';
import { context, fakeAppwrite, profile } from './helpers.mjs';

/**
 * The four server-side Functions behind one entrypoint.
 *
 * Their own suites cover what each does. What is new here is the
 * dispatch — an event must reach `on-write` and nothing else, a tick
 * must reach the sweeps and not `on-write` — and the isolation between
 * the sweeps, which were separate Functions a release ago and must not
 * start taking each other down.
 */
const at = (minute) => new Date(Date.UTC(2026, 9, 3, 12, minute));

/**
 * Runs `body` with the clock frozen at `minute` past the hour.
 *
 * Whether the sweep runs is decided from the clock, so a tick test left
 * on the real one asserts a different thing depending on the second it
 * starts — which is how the first version of this passed locally and
 * would have failed one minute in five in CI.
 */
async function atMinute(minute, body) {
    // The whole `Date`, not just `Date.now`: `tasksFor()` reads the
    // clock through `new Date()`, which V8 does not route through a
    // patched `Date.now` — so stubbing only that left the test running
    // on the real clock and asserting nothing one minute in five.
    const Real = Date;
    const frozen = Real.UTC(2026, 9, 3, 12, minute);
    globalThis.Date = class extends Real {
        constructor(...args) {
            super(...(args.length ? args : [frozen]));
        }
        static now() {
            return frozen;
        }
    };
    try {
        return await body();
    } finally {
        globalThis.Date = Real;
    }
}

describe('which task runs on a tick', () => {
    it('always drains and escalates, in that order', () => {
        // Escalation queues what is overdue and the drain delivers what
        // is queued; swapping them would delay every escalation by a
        // minute, which no assertion elsewhere would notice.
        for (const minute of [0, 1, 4, 5, 7, 59]) {
            const names = tasksFor(at(minute)).map(([name]) => name);
            assert.deepEqual(names.slice(0, 2), ['drain', 'escalate'], `minute ${minute}`);
        }
    });

    it('sweeps on every fifth minute, as its own cron did', () => {
        // `*/5 * * * *` became `minute % 5`. A sweep that ran every
        // minute would still be correct — it is idempotent — but it
        // would multiply the reads it costs by five.
        const sweeps = [];
        for (let minute = 0; minute < 60; minute++) {
            if (tasksFor(at(minute)).some(([name]) => name === 'reconcile')) sweeps.push(minute);
        }
        assert.deepEqual(sweeps, [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55]);
        assert.equal(sweeps.length, 60 / RECONCILE_EVERY_MINUTES);
    });

    it('decides the sweep minute in UTC', () => {
        // The container's clock is UTC and the cron was; reading local
        // minutes would be right only for whole-hour offsets, and
        // nothing in Nigeria or Frankfurt would have shown it.
        assert.equal(isSweepMinute(new Date('2026-10-03T12:05:00.000Z')), true);
        assert.equal(isSweepMinute(new Date('2026-10-03T12:06:00.000Z')), false);
    });

    it('names the runners the four Functions exported', () => {
        const byName = Object.fromEntries(tasksFor(at(0)));
        assert.equal(byName.drain, runDrain);
        assert.equal(byName.escalate, runEscalate);
        assert.equal(byName.reconcile, runReconcile);
    });
});

describe('an event delivery', () => {
    it('runs on-write and none of the sweeps', async () => {
        const fake = fakeAppwrite({
            rows: { reports: { r1: { $id: 'r1', status: 'pending' } } },
        });
        const ctx = context(
            { $id: 'r1', status: 'pending', userId: 'u1' },
            { event: 'databases.cradi.tables.reports.rows.r1.create' },
        );
        await worker(ctx);

        // The outbox got the event; nothing claimed or delivered it,
        // which is what a drain in the same run would have done.
        const outbox = Object.values(fake.store.notification_outbox ?? {});
        assert.equal(outbox.length, 1);
        assert.equal(outbox[0].processedAt ?? null, null);
        // And the response is the event handler's, not a tick summary.
        assert.equal(ctx.captured.body?.drain, undefined);
    });
});

describe('a scheduled tick', () => {
    it('reports each task and answers 200 when they all worked', async () => {
        await atMinute(3, async () => {
            fakeAppwrite({ rows: { profiles: { u1: profile() } } });
            const ctx = context({});
            await worker(ctx);

            assert.equal(ctx.captured.status, 200);
            assert.deepEqual(Object.keys(ctx.captured.body).sort(), ['drain', 'escalate']);
            assert.equal(ctx.captured.body.drain.claimed, 0);
        });
    });

    it('runs the sweep too when the clock says so', async () => {
        await atMinute(5, async () => {
            fakeAppwrite({ rows: { profiles: { u1: profile() } } });
            const ctx = context({});
            await worker(ctx);
            assert.ok('reconcile' in ctx.captured.body, JSON.stringify(ctx.captured.body));
        });
    });

    it('does not run on-write, which has no event to read', async () => {
        const fake = fakeAppwrite({ rows: { profiles: { u1: profile() } } });
        await worker(context({ $id: 'r1', status: 'pending' }));
        assert.deepEqual(Object.values(fake.store.notification_outbox ?? {}), []);
    });

    it('keeps going when one task throws, and says which', async () => {
        // These were four Functions a release ago: a crash in the sweep
        // never stopped the drain, and merging them must not change
        // that. Failing the drain, because it is the first — a later
        // task running proves the loop did not abort.
        fakeAppwrite({
            rows: { profiles: { u1: profile() } },
            fail: {
                'GET /tables/notification_outbox/rows': {
                    status: 500,
                    body: { message: 'boom', type: 'general_unknown' },
                },
            },
        });
        const ctx = context({});
        await worker(ctx);

        assert.equal(ctx.captured.body.drain.failed, true);
        assert.match(ctx.captured.body.drain.error, /boom|500/);
        // The one after it still ran. (`escalate`'s own summary has a
        // `failed` counter of its own, so this asks whether the worker
        // marked it dead, not whether that counter is zero.)
        assert.notEqual(ctx.captured.body.escalate.failed, true);
        assert.ok('escalate' in ctx.captured.body);
        // And the tick is visibly red rather than a clean 200.
        assert.equal(ctx.captured.status, 500);
    });
});
