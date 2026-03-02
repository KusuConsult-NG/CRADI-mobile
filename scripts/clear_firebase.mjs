#!/usr/bin/env node
import { readFileSync, existsSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, '..');
const KEY_PATH = resolve(ROOT, 'scripts/service-account-key.json');

if (!existsSync(KEY_PATH)) {
    console.error('service-account-key.json not found in scripts directory');
    process.exit(1);
}

let admin;
try {
    admin = (await import('firebase-admin')).default;
} catch {
    console.error('firebase-admin not installed');
    process.exit(1);
}

const serviceAccount = JSON.parse(readFileSync(KEY_PATH, 'utf8'));

admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
});

const auth = admin.auth();
const db = admin.firestore();

async function clearAuth() {
    console.log('Clearing Auth Users...');
    let deletedCount = 0;

    const listAllUsers = async (nextPageToken) => {
        const listUsersResult = await auth.listUsers(1000, nextPageToken);
        const uids = listUsersResult.users.map((userRecord) => userRecord.uid);

        if (uids.length > 0) {
            await auth.deleteUsers(uids);
            deletedCount += uids.length;
            console.log(`Deleted ${uids.length} users in this batch.`);
        }

        if (listUsersResult.pageToken) {
            await listAllUsers(listUsersResult.pageToken);
        }
    };

    await listAllUsers();
    console.log(`Finished clearing Auth Users. Total deleted: ${deletedCount}`);
}

async function deleteQueryBatch(query, resolve) {
    const snapshot = await query.get();

    const batchSize = snapshot.size;
    if (batchSize === 0) {
        resolve();
        return;
    }

    const batch = db.batch();
    snapshot.docs.forEach((doc) => {
        batch.delete(doc.ref);
    });
    await batch.commit();

    process.nextTick(() => {
        deleteQueryBatch(query, resolve);
    });
}

async function clearDB() {
    console.log('Clearing Firestore Collections...');
    const collections = await db.listCollections();
    for (const collection of collections) {
        const collectionPath = collection.id;
        console.log(`Deleting collection: ${collectionPath}`);
        const collectionRef = db.collection(collectionPath);
        const query = collectionRef.orderBy('__name__').limit(500);

        await new Promise((resolve, reject) => {
            deleteQueryBatch(query, resolve).catch(reject);
        });
    }
    console.log('Finished clearing Firestore Collections.');
}

async function main() {
    try {
        await clearAuth();
        await clearDB();
        console.log('Cleanup Complete!');
        process.exit(0);
    } catch (e) {
        console.error('Error during cleanup:', e);
        process.exit(1);
    }
}

main();
