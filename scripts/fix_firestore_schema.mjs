#!/usr/bin/env node
/**
 * CRADI/EWER Firestore Schema Fix Script
 * ========================================
 * Run: node scripts/fix_firestore_schema.mjs
 *
 * This script scans the existing Firestore collections (like 'reports' and 'users')
 * and backfills any missing schema fields that are expected by the application
 * (e.g., handling records that were created before certain fields were added).
 */

import { readFileSync, existsSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, '..');
const KEY_PATH = resolve(ROOT, 'scripts/service-account-key.json');

if (!existsSync(KEY_PATH)) {
    console.error('❌ service-account-key.json not found at ' + KEY_PATH);
    process.exit(1);
}

let admin;
try {
    admin = (await import('firebase-admin')).default;
} catch (e) {
    console.error('❌ firebase-admin not installed. Run: npm install firebase-admin');
    process.exit(1);
}

const serviceAccount = JSON.parse(readFileSync(KEY_PATH, 'utf8'));

admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

console.log('🚀 Starting Firestore Schema Fix Migration...\n');

async function fixReportsSchema() {
    console.log('📋 Checking [reports] collection...');
    const snapshot = await db.collection('reports').get();
    let updated = 0;

    for (const doc of snapshot.docs) {
        const data = doc.data();
        let needsUpdate = false;
        const updates = {};

        // 1. backfill submittedAt
        if (!data.submittedAt) {
            // Try to recover from createdAt, $createdAt, or fallback
            let timeStr = new Date().toISOString();
            if (data.createdAt) timeStr = data.createdAt;
            if (data.$createdAt) timeStr = data.$createdAt;
            // if object, maybe it's a timestamp
            if (typeof timeStr !== 'string') {
              if (timeStr.toDate) timeStr = timeStr.toDate().toISOString();
              else timeStr = new Date().toISOString();
            }
            updates.submittedAt = timeStr;
            needsUpdate = true;
        }

        // 2. backfill userId
        if (!data.userId) {
            if (data.excludeUserId) {
                updates.userId = data.excludeUserId;
                needsUpdate = true;
            } else if (data.$id) {
                updates.userId = data.$id;
                needsUpdate = true;
            }
        }

        // 3. backfill status
        if (!data.status) {
            updates.status = 'pending';
            needsUpdate = true;
        }

        // 4. backfill isAlert and fix severity names
        if (data.isAlert === undefined || data.severity?.includes('-')) {
            let severity = data.severity || '';
            // normalize severity text if needed since previous bug stored full string
            if (severity.toLowerCase().includes('critical')) {
                severity = 'critical';
                updates.severity = severity;
            } else if (severity.toLowerCase().includes('high')) {
                severity = 'high';
                updates.severity = severity;
            } else if (severity.toLowerCase().includes('medium')) {
                 severity = 'medium';
                 updates.severity = severity;
            } else if (severity.toLowerCase().includes('low')) {
                 severity = 'low';
                 updates.severity = severity;
            }

            updates.isAlert = (severity === 'critical' || severity === 'high');
            needsUpdate = true;
        }

        // 5. backfill verificationCount
        if (data.verificationCount === undefined) {
            updates.verificationCount = 0;
            needsUpdate = true;
        }
        
        // 6. Fix hazardType language leak (e.g., if Hausa 'Rikici' was stored instead of 'conflict')
        const hazardStr = data.hazardType || '';
        const hazardMap = {
            'Ambaliyar ruwa': 'flooding',
            'Zafi Mai Tsanani': 'extremeHeat',
            'Sadarwa da kwari': 'pestOutbreak',
            'Fari': 'drought',
            'Gobarar Daji': 'wildfire',
            'Guguwa tana gabatowa': 'incomingStorm',
            'Rikici': 'conflict'
        };
        if (hazardMap[hazardStr]) {
            updates.hazardType = hazardMap[hazardStr];
            needsUpdate = true;
        }

        if (needsUpdate) {
            await doc.ref.update(updates);
            updated++;
            console.log(`  ➕ Fixed report document: ${doc.id}`);
        }
    }
    console.log(`✅ Reports check complete. ${updated} documents updated.\n`);
}

async function fixUsersSchema() {
    console.log('📋 Checking [users] collection...');
    const snapshot = await db.collection('users').get();
    let updated = 0;

    for (const doc of snapshot.docs) {
        const data = doc.data();
        let needsUpdate = false;
        const updates = {};

        if (data.biometricsEnabled === undefined) {
            updates.biometricsEnabled = false;
            needsUpdate = true;
        }

        if (data.isVerified === undefined) {
            updates.isVerified = false;
            needsUpdate = true;
        }
        
        if (!data.role) {
            updates.role = 'user';
            needsUpdate = true;
        }

        if (needsUpdate) {
            await doc.ref.update(updates);
            updated++;
            console.log(`  ➕ Fixed user document: ${doc.id}`);
        }
    }
    console.log(`✅ Users check complete. ${updated} documents updated.\n`);
}

async function run() {
    try {
        await fixReportsSchema();
        await fixUsersSchema();
        console.log('✨ Schema config fixing completed successfully!');
    } catch (e) {
        console.error('❌ Error fixing schema:', e);
    } finally {
        await admin.app().delete();
    }
}

run();
