/**
 * clear_appwrite_data.mjs
 * Deletes ALL users from Appwrite Auth and ALL documents from every collection.
 * Requires: npm install node-appwrite
 * Usage:    APPWRITE_API_KEY=<your_key> node clear_appwrite_data.mjs
 */

import { Client, Users, Databases, Query } from 'node-appwrite';

// ── Config ──────────────────────────────────────────────────────────────────
const ENDPOINT = 'https://fra.cloud.appwrite.io/v1';
const PROJECT_ID = '6941cdb400050e7249d5';
const DATABASE_ID = '6941e2c2003705bb5a25';
const API_KEY = process.env.APPWRITE_API_KEY;

const COLLECTIONS = [
    'users',
    'reports',
    'emergency_contacts',
    'trusted_devices',
    'login_history',
    'chats',
    'messages',
    'alerts',
    'knowledge_base',
];

if (!API_KEY) {
    console.error('❌  Missing API key. Run with: APPWRITE_API_KEY=<your_key> node clear_appwrite_data.mjs');
    process.exit(1);
}

// ── Client ───────────────────────────────────────────────────────────────────
const client = new Client()
    .setEndpoint(ENDPOINT)
    .setProject(PROJECT_ID)
    .setKey(API_KEY);

const users = new Users(client);
const databases = new Databases(client);

// ── Helpers ──────────────────────────────────────────────────────────────────

/** Delete all auth users (paginated) */
async function deleteAllAuthUsers() {
    console.log('\n🔐  Deleting Auth users...');
    let deleted = 0;

    while (true) {
        const list = await users.list([Query.limit(100)]);
        if (list.users.length === 0) break;

        for (const user of list.users) {
            await users.delete(user.$id);
            console.log(`   ✓ Auth user deleted: ${user.email || user.$id}`);
            deleted++;
        }
    }

    console.log(`   → ${deleted} auth user(s) deleted.`);
    return deleted;
}

/** Delete all documents in a collection (paginated) */
async function deleteAllDocuments(collectionId) {
    let deleted = 0;

    while (true) {
        let list;
        try {
            list = await databases.listDocuments(DATABASE_ID, collectionId, [Query.limit(100)]);
        } catch (e) {
            // Collection may not exist yet — skip gracefully
            if (e.code === 404) {
                console.log(`   ⚠️  Collection "${collectionId}" not found — skipping.`);
                return 0;
            }
            throw e;
        }

        if (list.documents.length === 0) break;

        for (const doc of list.documents) {
            await databases.deleteDocument(DATABASE_ID, collectionId, doc.$id);
            deleted++;
        }
    }

    return deleted;
}

// ── Main ─────────────────────────────────────────────────────────────────────
async function main() {
    console.log('🧹  Appwrite Data Cleaner');
    console.log(`    Project: ${PROJECT_ID}`);
    console.log(`    Endpoint: ${ENDPOINT}\n`);

    // 1. Auth users
    const authDeleted = await deleteAllAuthUsers();

    // 2. Database collections
    console.log('\n🗄️   Deleting database documents...');
    const results = {};
    for (const col of COLLECTIONS) {
        const count = await deleteAllDocuments(col);
        results[col] = count;
        console.log(`   ✓ [${col}] — ${count} document(s) deleted.`);
    }

    // 3. Summary
    console.log('\n✅  Done!');
    console.log(`    Auth users deleted : ${authDeleted}`);
    console.log('    Documents deleted:');
    for (const [col, count] of Object.entries(results)) {
        if (count > 0) console.log(`      ${col}: ${count}`);
    }
}

main().catch(err => {
    console.error('❌  Error:', err.message ?? err);
    process.exit(1);
});
