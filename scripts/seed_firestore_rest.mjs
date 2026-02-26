#!/usr/bin/env node
/**
 * CRADI/EWER Firestore Seed Script (REST API — no key file required)
 * ===================================================================
 * Uses Firestore REST API + existing gcloud auth token.
 * Run: node scripts/seed_firestore_rest.mjs
 *
 * Requirements:
 *  - gcloud CLI installed and `gcloud auth login` already done
 *  - Node.js >= 18 (uses native fetch)
 */
import { execSync } from 'child_process';

const PROJECT = 'ewer-8f788';
const BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;

// ── Get auth token ────────────────────────────────────────────────────────────
let TOKEN;
try {
    TOKEN = execSync('gcloud auth print-access-token', { encoding: 'utf8', stdio: 'pipe' }).trim();
} catch {
    console.error('\x1b[31m✗\x1b[0m gcloud not authenticated. Run: gcloud auth login');
    process.exit(1);
}

const headers = {
    'Authorization': `Bearer ${TOKEN}`,
    'Content-Type': 'application/json',
};

// ── Helpers ───────────────────────────────────────────────────────────────────
function toFirestoreValue(val) {
    if (typeof val === 'string') return { stringValue: val };
    if (typeof val === 'boolean') return { booleanValue: val };
    if (typeof val === 'number') return { integerValue: String(val) };
    if (val === null) return { nullValue: null };
    if (val instanceof Date) return { timestampValue: val.toISOString() };
    if (typeof val === 'object') {
        return {
            mapValue: {
                fields: Object.fromEntries(
                    Object.entries(val).map(([k, v]) => [k, toFirestoreValue(v)])
                ),
            },
        };
    }
    return { stringValue: String(val) };
}

function toFirestoreDoc(data) {
    return { fields: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, toFirestoreValue(v)])) };
}

async function queryWhere(collection, field, value) {
    const res = await fetch(`${BASE}:runQuery`, {
        method: 'POST',
        headers,
        body: JSON.stringify({
            structuredQuery: {
                from: [{ collectionId: collection }],
                where: {
                    fieldFilter: {
                        field: { fieldPath: field },
                        op: 'EQUAL',
                        value: toFirestoreValue(value),
                    },
                },
                limit: 1,
            },
        }),
    });
    const json = await res.json();
    return json[0]?.document ? [json[0].document] : [];
}

async function addDoc(collection, data) {
    const res = await fetch(`${BASE}/${collection}`, {
        method: 'POST',
        headers,
        body: JSON.stringify(toFirestoreDoc({ ...data, createdAt: new Date().toISOString(), updatedAt: new Date().toISOString() })),
    });
    if (!res.ok) throw new Error(`Firestore error ${res.status}: ${await res.text()}`);
    return res.json();
}

async function setDoc(collection, docId, data) {
    const res = await fetch(`${BASE}/${collection}/${docId}`, {
        method: 'PATCH',
        headers,
        body: JSON.stringify(toFirestoreDoc({ ...data, createdAt: new Date().toISOString() })),
    });
    if (!res.ok) throw new Error(`Firestore error ${res.status}: ${await res.text()}`);
    return res.json();
}

async function getDoc(collection, docId) {
    const res = await fetch(`${BASE}/${collection}/${docId}`, { headers });
    if (res.status === 404) return null;
    return res.json();
}

const ok = (msg) => console.log(`\x1b[32m✓\x1b[0m ${msg}`);
const skip = (msg) => console.log(`\x1b[33m⚠\x1b[0m Skipped (exists): ${msg}`);

// ─────────────────────────────────────────────────────────────────────────────
console.log(`\n\x1b[36m→\x1b[0m Seeding Firestore for project ${PROJECT}...\n`);
// ─────────────────────────────────────────────────────────────────────────────

// 1. Knowledge base guides
const guides = [
    { title: 'Flood Preparedness Guide', category: 'flood', content: 'Know your flood risk zone. Keep emergency supplies elevated. Subscribe to early warning alerts.', iconName: 'water', iconColor: 'blue', severity: 'high', isActive: true },
    { title: 'Drought Warning Response', category: 'drought', content: 'Monitor rainfall forecasts. Report abnormal dryness. Practice water conservation.', iconName: 'water_drop', iconColor: 'orange', severity: 'medium', isActive: true },
    { title: 'Wildfire Safety Guide', category: 'wildfire', content: 'Maintain a defensible space. Prepare an evacuation bag. Know your local evacuation routes.', iconName: 'local_fire_department', iconColor: 'red', severity: 'critical', isActive: true },
    { title: 'Pest Outbreak Response', category: 'pest', content: 'Report crop damage early. Coordinate with local agricultural officials. Document affected area.', iconName: 'pest_control', iconColor: 'green', severity: 'medium', isActive: true },
    { title: 'Extreme Heat Protocol', category: 'heat', content: 'Stay hydrated. Avoid outdoor activity between 11am-3pm. Check on vulnerable neighbours.', iconName: 'thermostat', iconColor: 'red', severity: 'high', isActive: true },
    { title: 'Windstorm Safety Guide', category: 'windstorm', content: 'Secure outdoor items. Stay indoors during storms. Report downed power lines immediately.', iconName: 'air', iconColor: 'grey', severity: 'high', isActive: true },
    { title: 'Erosion Monitoring Guide', category: 'erosion', content: 'Report gullies forming near farmland. Document location with GPS coordinates. Alert local council.', iconName: 'terrain', iconColor: 'brown', severity: 'medium', isActive: true },
];

for (const guide of guides) {
    const exists = await queryWhere('knowledge_base', 'title', guide.title);
    if (exists.length === 0) {
        await addDoc('knowledge_base', guide);
        ok(guide.title);
    } else {
        skip(guide.title);
    }
}

// 2. App config
const configExists = await getDoc('config', 'app_settings');
if (!configExists || configExists.error) {
    await setDoc('config', 'app_settings', {
        minimumVerifications: 2,
        escalationHours: 24,
        maxReportImagesPerSubmission: 5,
        featFlags: { chatEnabled: true, knowledgeBaseEnabled: true, peerVerificationEnabled: true },
    });
    ok('config/app_settings');
} else {
    skip('config/app_settings');
}

console.log('\n\x1b[32m\x1b[1m🎉 Seeding complete!\x1b[0m\n');
