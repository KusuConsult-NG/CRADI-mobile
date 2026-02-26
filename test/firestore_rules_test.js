// Firestore Security Rules Integration Tests
// Run: firebase emulators:exec --only firestore "node test/firestore_rules_test.js"
// Requires: npm install @firebase/rules-unit-testing firebase-admin

const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const { readFileSync } = require('fs');
const path = require('path');

let testEnv;

const PROJECT_ID = 'ewer-8f788';

beforeAll(async () => {
    testEnv = await initializeTestEnvironment({
        projectId: PROJECT_ID,
        firestore: {
            rules: readFileSync(path.join(__dirname, '../firestore.rules'), 'utf8'),
            host: 'localhost',
            port: 8080,
        },
    });
});

afterAll(async () => {
    await testEnv.cleanup();
});

afterEach(async () => {
    await testEnv.clearFirestore();
});

// ── Helpers ──────────────────────────────────────────────────────────────────

function unauthedDb() {
    return testEnv.unauthenticatedContext().firestore();
}

function authedDb(uid, claims = {}) {
    return testEnv.authenticatedContext(uid, claims).firestore();
}

// ── USERS collection ─────────────────────────────────────────────────────────

describe('users/', () => {
    test('unauthenticated read is denied', async () => {
        await assertFails(unauthedDb().collection('users').doc('user1').get());
    });

    test('authenticated user can read their own profile', async () => {
        const db = authedDb('user1');
        await assertSucceeds(db.collection('users').doc('user1').get());
    });

    test('authenticated user cannot read another user profile', async () => {
        const db = authedDb('user1');
        await assertFails(db.collection('users').doc('user2').get());
    });

    test('user can update their own profile', async () => {
        const db = authedDb('user1');
        await assertSucceeds(db.collection('users').doc('user1').set({ name: 'Test' }));
    });

    test('user cannot update another profile', async () => {
        const db = authedDb('user1');
        await assertFails(db.collection('users').doc('user2').set({ name: 'Hacker' }));
    });
});

// ── REPORTS collection ───────────────────────────────────────────────────────

describe('reports/', () => {
    test('unauthenticated read is denied', async () => {
        await assertFails(unauthedDb().collection('reports').get());
    });

    test('authenticated user can list reports', async () => {
        const db = authedDb('user1');
        await assertSucceeds(db.collection('reports').get());
    });

    test('authenticated user can create a report', async () => {
        const db = authedDb('user1');
        await assertSucceeds(db.collection('reports').add({
            userId: 'user1',
            hazardType: 'flood',
            status: 'pending',
        }));
    });

    test('user can update their own report', async () => {
        // Seed a report
        await testEnv.withSecurityRulesDisabled(async (ctx) => {
            await ctx.firestore().collection('reports').doc('report1').set({
                userId: 'user1', status: 'pending',
            });
        });
        const db = authedDb('user1');
        await assertSucceeds(db.collection('reports').doc('report1').update({ status: 'updated' }));
    });

    test('user cannot update another user report', async () => {
        await testEnv.withSecurityRulesDisabled(async (ctx) => {
            await ctx.firestore().collection('reports').doc('report2').set({
                userId: 'user2', status: 'pending',
            });
        });
        const db = authedDb('user1');
        await assertFails(db.collection('reports').doc('report2').update({ status: 'hacked' }));
    });
});

// ── ALERTS collection ────────────────────────────────────────────────────────

describe('alerts/', () => {
    test('authenticated user can read alerts', async () => {
        const db = authedDb('user1');
        await assertSucceeds(db.collection('alerts').get());
    });

    test('authenticated user cannot write alerts (read-only)', async () => {
        const db = authedDb('user1');
        await assertFails(db.collection('alerts').add({ type: 'flood' }));
    });

    test('unauthenticated read is denied', async () => {
        await assertFails(unauthedDb().collection('alerts').get());
    });
});

// ── KNOWLEDGE_BASE collection ─────────────────────────────────────────────────

describe('knowledge_base/', () => {
    test('authenticated user can read knowledge base', async () => {
        const db = authedDb('user1');
        await assertSucceeds(db.collection('knowledge_base').get());
    });

    test('authenticated user cannot write knowledge base', async () => {
        const db = authedDb('user1');
        await assertFails(db.collection('knowledge_base').add({ title: 'Hack' }));
    });
});

// ── MESSAGES collection ───────────────────────────────────────────────────────

describe('messages/', () => {
    test('unauthenticated read is denied', async () => {
        await assertFails(unauthedDb().collection('messages').get());
    });

    test('authenticated user can read messages', async () => {
        const db = authedDb('user1');
        await assertSucceeds(db.collection('messages').get());
    });

    test('authenticated user can send a message', async () => {
        const db = authedDb('user1');
        await assertSucceeds(db.collection('messages').add({
            senderId: 'user1',
            message: 'Hello',
        }));
    });
});
