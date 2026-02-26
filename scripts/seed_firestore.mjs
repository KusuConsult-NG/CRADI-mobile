#!/usr/bin/env node
/**
 * CRADI/EWER Firestore Seed Script
 * ==================================
 * Project: ewer-8f788
 * Run: node scripts/seed_firestore.mjs
 *
 * Seeds the Firestore database with:
 *  - An initial admin user document (if none exists)
 *  - Sample knowledge-base guide entries
 *  - Sample hazard types for the alert taxonomy
 *
 * Requires: npm install firebase-admin
 * Requires a service account key at: scripts/service-account-key.json
 * (Download from Firebase Console → Project Settings → Service Accounts)
 */

import { readFileSync, existsSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, '..');
const KEY_PATH = resolve(ROOT, 'scripts/service-account-key.json');

// ── Validate service account key ──────────────────────────────────────────────
if (!existsSync(KEY_PATH)) {
    console.error('\x1b[31m✗\x1b[0m service-account-key.json not found at scripts/service-account-key.json');
    console.error('  → Download from: Firebase Console → Project Settings → Service Accounts → Generate new private key');
    process.exit(1);
}

// ── Dynamic import of firebase-admin ─────────────────────────────────────────
let admin;
try {
    admin = (await import('firebase-admin')).default;
} catch {
    console.error('\x1b[31m✗\x1b[0m firebase-admin not installed. Run: npm install firebase-admin');
    process.exit(1);
}

const serviceAccount = JSON.parse(readFileSync(KEY_PATH, 'utf8'));

admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

console.log('\n\x1b[36m→\x1b[0m Seeding Firestore...\n');

// ─────────────────────────────────────────────────────────────────────────────
// 1. Knowledge Base — sample guide entries
// ─────────────────────────────────────────────────────────────────────────────
const knowledgeGuides = [
    // ── English guides ────────────────────────────────────────────────────────
    {
        title: 'Flood Preparedness Guide',
        category: 'flood',
        language: 'en',
        content: 'Know your flood risk zone. Keep emergency supplies elevated. Subscribe to early warning alerts.',
        iconName: 'water',
        iconColor: 'blue',
        severity: 'high',
        isActive: true,
        searchKeywords: ['flood', 'water', 'preparedness', 'emergency', 'alert', 'risk'],
    },
    {
        title: 'Drought Warning Response',
        category: 'drought',
        language: 'en',
        content: 'Monitor rainfall forecasts. Report abnormal dryness. Practice water conservation.',
        iconName: 'water_drop',
        iconColor: 'orange',
        severity: 'medium',
        isActive: true,
        searchKeywords: ['drought', 'rainfall', 'water', 'conservation', 'dry'],
    },
    {
        title: 'Wildfire Safety Guide',
        category: 'wildfire',
        language: 'en',
        content: 'Maintain a defensible space. Prepare an evacuation bag. Know your local evacuation routes.',
        iconName: 'local_fire_department',
        iconColor: 'red',
        severity: 'critical',
        isActive: true,
        searchKeywords: ['fire', 'wildfire', 'evacuation', 'safety', 'emergency'],
    },
    {
        title: 'Pest Outbreak Response',
        category: 'pest',
        language: 'en',
        content: 'Report crop damage early. Coordinate with local agricultural officials. Document affected area.',
        iconName: 'pest_control',
        iconColor: 'green',
        severity: 'medium',
        isActive: true,
        searchKeywords: ['pest', 'crop', 'farm', 'agriculture', 'outbreak', 'damage'],
    },
    {
        title: 'Extreme Heat Protocol',
        category: 'heat',
        language: 'en',
        content: 'Stay hydrated. Avoid outdoor activity between 11am–3pm. Check on vulnerable neighbours.',
        iconName: 'thermostat',
        iconColor: 'red',
        severity: 'high',
        isActive: true,
        searchKeywords: ['heat', 'temperature', 'hydration', 'sun', 'hot'],
    },

    // ── Hausa guides (Hausa translations) ────────────────────────────────────
    {
        title: 'Jagorar Shirye-shiryen Ambaliya',
        category: 'flood',
        language: 'ha',
        content: 'Sanin yankin da yake cikin haɗarin ambaliya. Ajiye kayan agajin gaggawa a wuri mai tsawo. Yi rajista don karɓar faɗakarwar bala\'i da wuri.',
        iconName: 'water',
        iconColor: 'blue',
        severity: 'high',
        isActive: true,
        searchKeywords: ['ambaliya', 'ruwa', 'shirye-shirye', 'magunguna', 'faɗakarwa'],
    },
    {
        title: 'Mayar da Martani ga Fari',
        category: 'drought',
        language: 'ha',
        content: 'Sa ido kan hasashen ruwan sama. Bayar da rahoton rashin danshi. Yi amfani da ruwa da kiyayewa.',
        iconName: 'water_drop',
        iconColor: 'orange',
        severity: 'medium',
        isActive: true,
        searchKeywords: ['fari', 'ruwa', 'bushe', 'noma', 'kiyayewa'],
    },
    {
        title: 'Jagorar Tsaro daga Gobarar Daji',
        category: 'wildfire',
        language: 'ha',
        content: 'Kula da sarari mai tsaro. Shirya jakar evacuations. Sanin hanyoyin ficewa a gida.',
        iconName: 'local_fire_department',
        iconColor: 'red',
        severity: 'critical',
        isActive: true,
        searchKeywords: ['gobara', 'wuta', 'daji', 'ficewa', 'tsaro'],
    },
    {
        title: 'Mayar da Martani ga Barkewar Kwari',
        category: 'pest',
        language: 'ha',
        content: 'Bayar da rahoton lalacewar amfanin gona da wuri. Yi haɗin gwiwa da jami\'an aikin gona. Rubuta yankin da abin ya shafa.',
        iconName: 'pest_control',
        iconColor: 'green',
        severity: 'medium',
        isActive: true,
        searchKeywords: ['kwari', 'amfanin gona', 'noma', 'lalacewa', 'rikici'],
    },
    {
        title: 'Ka\'idojin Zafi Mai Tsanani',
        category: 'heat',
        language: 'ha',
        content: 'Sha ruwa sosai. Guji ayyukan waje daga 11am zuwa 3pm. Kula da maƙwabtan da ke cikin haɗari.',
        iconName: 'thermostat',
        iconColor: 'red',
        severity: 'high',
        isActive: true,
        searchKeywords: ['zafi', 'rana', 'ruwa', 'lafiya', 'tashin zafi'],
    },
];

const knowledgeRef = db.collection('knowledge_base');
for (const guide of knowledgeGuides) {
    const existing = await knowledgeRef.where('title', '==', guide.title).limit(1).get();
    if (existing.empty) {
        await knowledgeRef.add({
            ...guide,
            $createdAt: admin.firestore.FieldValue.serverTimestamp(),
            $updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        console.log(`\x1b[32m✓\x1b[0m Seeded knowledge guide: ${guide.title}`);
    } else {
        console.log(`\x1b[33m⚠\x1b[0m Skipped (already exists): ${guide.title}`);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. Seed a system configuration document (app version, feature flags)
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
        $createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log('\x1b[32m✓\x1b[0m Seeded config/app_settings');
} else {
    console.log('\x1b[33m⚠\x1b[0m Skipped config/app_settings (already exists)');
}

console.log('\n\x1b[32m\x1b[1m🎉 Seeding complete!\x1b[0m\n');
await admin.app().delete();
