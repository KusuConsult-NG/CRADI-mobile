import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import client, { routeFor } from '../src/client.js';
import auth from '../src/auth.js';
import operation from '../src/operation.js';
import write from '../src/write.js';
import { context, fakeAppwrite, profile } from './helpers.mjs';

/**
 * The three client-facing Functions behind one entrypoint.
 *
 * What is worth testing here is not what each handler does — their own
 * suites cover that — but that the dispatcher reaches the right one and
 * that nothing is reachable it should not be. A router that quietly
 * answered every path with `write` would pass every other test in this
 * directory.
 */
describe('routing on the execution path', () => {
    it('maps each path to its own handler', () => {
        // Identity, not behaviour: a handler swapped for another would
        // otherwise only show up as a wrong refusal somewhere far away.
        assert.equal(routeFor('/write'), write);
        assert.equal(routeFor('/auth'), auth);
        assert.equal(routeFor('/operation'), operation);
    });

    it('tolerates the spellings a caller may send', () => {
        // Appwrite passes the path through as given, and the SDKs differ
        // on the leading slash.
        for (const spelling of ['write', '/write', '/write/', '//write', ' /write ']) {
            assert.equal(routeFor(spelling), write, spelling);
        }
    });

    it('has no route for anything else', () => {
        for (const path of ['/', '', null, undefined, '/drain', '/writes', '/WRITE']) {
            assert.equal(routeFor(path), null, String(path));
        }
    });

    it('answers an unknown path with a named 404', async () => {
        // A wrong path used to be Appwrite's own 404 naming the Function.
        // Now the Function exists and the path does not, so the refusal
        // has to name itself or a caller sees a silent nothing.
        const ctx = context({}, { path: '/nope' });
        await client(ctx);

        assert.equal(ctx.captured.status, 404);
        assert.equal(ctx.captured.body.type, 'general_route_not_found');
        assert.match(ctx.captured.body.message, /\/nope/);
        assert.match(ctx.captured.body.message, /\/write/);
    });

    it('answers the empty path with a 404 rather than guessing', async () => {
        // The default when a caller forgets `path:` entirely. Picking a
        // handler for it would make every such caller silently wrong.
        const ctx = context({}, { path: '/' });
        await client(ctx);
        assert.equal(ctx.captured.status, 404);
    });
});

describe('the routes reach the handlers they name', () => {
    it('/operation runs the operation handler', async () => {
        const fake = fakeAppwrite({
            rows: {
                profiles: { u1: profile({ role: 'ewr' }) },
                reports: { r1: { $id: 'r1', status: 'approved' } },
            },
        });
        const ctx = context(
            { operation: 'reopen_report', params: { p_report_id: 'r1' } },
            { path: '/operation' },
        );
        await client(ctx);

        assert.equal(ctx.captured.status, 200);
        assert.equal(fake.store.reports.r1.status, 'pending');
    });

    it('/write runs the write handler', async () => {
        const fake = fakeAppwrite({ rows: { profiles: { u1: profile() } } });
        const ctx = context(
            {
                op: 'create',
                collection: 'reports',
                documentId: 'r9',
                data: {
                    hazardType: 'flood',
                    title: 'Water over the road',
                    description: 'Rising since dawn',
                    state: 'Benue',
                    lga: 'Makurdi',
                    ward: 'North Bank I',
                },
            },
            { path: '/write' },
        );
        await client(ctx);

        assert.equal(ctx.captured.status, 200, JSON.stringify(ctx.captured.body));
        assert.ok(fake.store.reports.r9, 'the row was written');
    });

    it('/auth is reachable without a session', async () => {
        // The reason the merged Function is `execute: ['any']`:
        // registration and recovery happen before there is one.
        fakeAppwrite();
        const ctx = context({ action: 'sendRecoveryCode' }, { userId: null, path: '/auth' });
        await client(ctx);

        // Whatever it answers, it must not be the router's 404 — that
        // would mean a guest cannot start a recovery at all.
        assert.notEqual(ctx.captured.body?.type, 'general_route_not_found');
    });

    it('still refuses a guest on /write, now from the handler', async () => {
        // `write` was `execute: ['users']` and the merged Function is
        // `['any']`. The 401 has to survive that, or the widening is a
        // hole rather than a dispatch detail.
        const fake = fakeAppwrite({ rows: { profiles: { u1: profile() } } });
        const ctx = context(
            { op: 'create', collection: 'reports', documentId: 'r9', data: {} },
            { userId: null, path: '/write' },
        );
        await client(ctx);

        assert.equal(ctx.captured.status, 401);
        assert.equal(fake.store.reports?.r9, undefined);
    });

    it('still refuses a guest on /operation', async () => {
        fakeAppwrite({ rows: { reports: { r1: { $id: 'r1', status: 'approved' } } } });
        const ctx = context(
            { operation: 'reopen_report', params: { p_report_id: 'r1' } },
            { userId: null, path: '/operation' },
        );
        await client(ctx);
        assert.equal(ctx.captured.status, 401);
    });
});
