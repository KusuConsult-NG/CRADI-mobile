#!/usr/bin/env node
/**
 * CRADI/EWER Firestore Seed Script (Token-Based)
 * ================================================
 * Uses the existing `gcloud auth` token — no service account key file needed.
 * Run: node scripts/seed_firestore_token.mjs
 *
 * Requirements:
 *  - npm install firebase-admin
 *  - gcloud CLI installed and authenticated: gcloud auth login
 */
import { execSync } from 'child_process';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));

// ── Get fresh gcloud access token ────────────────────────────────────────────
let accessToken;
try {
    accessToken = execSync('gcloud auth print-access-token', {
        encoding: 'utf8',
        stdio: ['pipe', 'pipe', 'pipe'],
    }).trim();
} catch (e) {
    console.error('\x1b[31m✗\x1b[0m Failed to get gcloud access token.');
    console.error('  Run: gcloud auth login  then try again.');
    process.exit(1);
}

// ── Load firebase-admin ───────────────────────────────────────────────────────
let admin;
try {
    admin = (await import('firebase-admin')).default;
} catch {
    console.error('\x1b[31m✗\x1b[0m firebase-admin not installed. Run: npm install firebase-admin');
    process.exit(1);
}

// ── Custom credential using the access token ──────────────────────────────────
const customCredential = {
    getAccessToken: () =>
        Promise.resolve({
            access_token: accessToken,
            expires_in: 3600,
        }),
};

admin.initializeApp({
    credential: customCredential,
    projectId: 'ewer-8f788',
});

const db = admin.firestore();

console.log('\n\x1b[36m→\x1b[0m Seeding Firestore for project ewer-8f788...\n');

// ─────────────────────────────────────────────────────────────────────────────
// 1. Knowledge Base — hazard guide entries
// ─────────────────────────────────────────────────────────────────────────────
const knowledgeGuides = [
    {
        title: 'Flood Preparedness Guide',
        category: 'flood',
        content: 'Know your flood risk zone. Keep emergency supplies elevated. Subscribe to early warning alerts.',
        iconName: 'water',
        iconColor: 'blue',
        severity: 'high',
        isActive: true,
    },
    {
        title: 'Drought Warning Response',
        category: 'drought',
        content: 'Monitor rainfall forecasts. Report abnormal dryness. Practice water conservation.',
        iconName: 'water_drop',
        iconColor: 'orange',
        severity: 'medium',
        isActive: true,
    },
    {
        title: 'Wildfire Safety Guide',
        category: 'wildfire',
        content: 'Maintain a defensible space. Prepare an evacuation bag. Know your local evacuation routes.',
        iconName: 'local_fire_department',
        iconColor: 'red',
        severity: 'critical',
        isActive: true,
    },
    {
        title: 'Pest Outbreak Response',
        category: 'pest',
        content: 'Report crop damage early. Coordinate with local agricultural officials. Document affected area.',
        iconName: 'pest_control',
        iconColor: 'green',
        severity: 'medium',
        isActive: true,
    },
    {
        title: 'Extreme Heat Protocol',
        category: 'heat',
        content: 'Stay hydrated. Avoid outdoor activity between 11am-3pm. Check on vulnerable neighbours.',
        iconName: 'thermostat',
        iconColor: 'red',
        severity: 'high',
        isActive: true,
    },
    {
        title: 'Windstorm Safety Guide',
        category: 'windstorm',
        content: 'Secure outdoor items. Stay indoors during storms. Report downed power lines immediately.',
        iconName: 'air',
        iconColor: 'grey',
        severity: 'high',
        isActive: true,
    },
    {
        title: 'Erosion Monitoring Guide',
        category: 'erosion',
        content: 'Report gullies forming near farmland. Document location with GPS coordinates. Alert local council.',
        iconName: 'terrain',
        iconColor: 'brown',
        severity: 'medium',
        isActive: true,
    },
];

const knowledgeRef = db.collection('knowledge_base');
for (const guide of knowledgeGuides) {
    const existing = await knowledgeRef.where('title', '==', guide.title).limit(1).get();
    if (existing.empty) {
        await knowledgeRef.add({
            ...guide,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        console.log(`\x1b[32m✓\x1b[0m Seeded: ${guide.title}`);
    } else {
        console.log(`\x1b[33m⚠\x1b[0m Skipped (exists): ${guide.title}`);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. App configuration
// ─────────────────────────────────────────────────────────────────────────────
const configRef = db.collection('config').doc('app_settings');
const configSnap = await configRef.get();
if (!configSnap.exists) {
    await configRef.set({
        minimumVerifications: 2,
        escalationHours: 24,
        maxReportImagesPerSubmission: 5,
        featFlags: {
            chatEnabled: true,
            knowledgeBaseEnabled: true,
            peerVerificationEnabled: true,
        },
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log('\x1b[32m✓\x1b[0m Seeded: config/app_settings');
} else {
    console.log('\x1b[33m⚠\x1b[0m Skipped (exists): config/app_settings');
}

console.log('\n\x1b[32m\x1b[1m🎉 Seeding complete!\x1b[0m\n');
await admin.app().delete();
