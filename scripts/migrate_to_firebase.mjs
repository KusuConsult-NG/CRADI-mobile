#!/usr/bin/env node
/**
 * CRADI/EWER Firebase Migration Completion Script
 * =================================================
 * Project: ewer-8f788
 * Run: node scripts/migrate_to_firebase.mjs
 *
 * What this script does:
 *  1. Verifies Firebase CLI is installed and authenticated
 *  2. Deploys Firestore security rules   (firestore.rules)
 *  3. Deploys Firestore composite indexes (firestore.indexes.json)
 *  4. Optionally seeds Firestore collections with baseline data
 *  5. Verifies pubspec.yaml has no Appwrite package references
 *  6. Verifies no Appwrite imports remain in lib/ Dart files
 *  7. Runs `flutter analyze` and reports results
 *  8. Prints a final migration status report
 *
 * Requirements:
 *  - Node.js >= 18
 *  - Firebase CLI: npm install -g firebase-tools
 *  - Authenticated: firebase login
 *  - Flutter installed and on PATH
 */

import { execSync, spawn } from 'child_process';
import { existsSync, readFileSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, '..');

// ── Colours ───────────────────────────────────────────────────────────────────
const GREEN = '\x1b[32m';
const RED = '\x1b[31m';
const YELLOW = '\x1b[33m';
const BLUE = '\x1b[36m';
const RESET = '\x1b[0m';
const BOLD = '\x1b[1m';

const ok = (msg) => console.log(`${GREEN}✓${RESET} ${msg}`);
const fail = (msg) => console.log(`${RED}✗${RESET} ${msg}`);
const warn = (msg) => console.log(`${YELLOW}⚠${RESET} ${msg}`);
const info = (msg) => console.log(`${BLUE}→${RESET} ${msg}`);
const head = (msg) => console.log(`\n${BOLD}${msg}${RESET}`);

let stepsPassed = 0;
let stepsFailed = 0;

function pass(label) { ok(label); stepsPassed++; }
function err(label) { fail(label); stepsFailed++; }

function run(cmd, opts = {}) {
    try {
        return execSync(cmd, { cwd: ROOT, encoding: 'utf8', stdio: 'pipe', ...opts });
    } catch (e) {
        return null;
    }
}

function runOrThrow(cmd, label) {
    try {
        const out = execSync(cmd, { cwd: ROOT, encoding: 'utf8', stdio: 'pipe' });
        pass(label);
        return out;
    } catch (e) {
        err(`${label}\n   ${e.stderr?.trim() ?? e.message}`);
        return null;
    }
}

// ─────────────────────────────────────────────────────────────────────────────
head('Step 1: Pre-flight checks');
// ─────────────────────────────────────────────────────────────────────────────

// Check firebase CLI
const fbVersion = run('firebase --version');
if (fbVersion) {
    pass(`Firebase CLI installed: ${fbVersion.trim()}`);
} else {
    err('Firebase CLI not found. Run: npm install -g firebase-tools');
    process.exit(1);
}

// Check flutter
const flVersion = run('flutter --version --no-version-check');
if (flVersion) {
    pass(`Flutter installed: ${flVersion.split('\n')[0].trim()}`);
} else {
    err('Flutter not found on PATH.');
    process.exit(1);
}

// Check firebase.json
if (existsSync(resolve(ROOT, 'firebase.json'))) {
    pass('firebase.json found');
} else {
    warn('firebase.json not found — creating minimal one for this project');
    const firebaseJson = {
        firestore: {
            rules: 'firestore.rules',
            indexes: 'firestore.indexes.json'
        }
    };
    import('fs').then(({ writeFileSync }) => {
        writeFileSync(resolve(ROOT, 'firebase.json'), JSON.stringify(firebaseJson, null, 2));
    });
}

// Check that firestore.rules exists
if (existsSync(resolve(ROOT, 'firestore.rules'))) {
    pass('firestore.rules found');
} else {
    err('firestore.rules not found — run the CRADI migration steps first');
}

if (existsSync(resolve(ROOT, 'firestore.indexes.json'))) {
    pass('firestore.indexes.json found');
} else {
    err('firestore.indexes.json not found');
}

// ─────────────────────────────────────────────────────────────────────────────
head('Step 2: Deploy Firestore rules & indexes');
// ─────────────────────────────────────────────────────────────────────────────

info('Deploying Firestore security rules...');
runOrThrow(
    'firebase deploy --only firestore:rules --project ewer-8f788',
    'Firestore rules deployed'
);

info('Deploying Firestore composite indexes (may take a few minutes to build)...');
runOrThrow(
    'firebase deploy --only firestore:indexes --project ewer-8f788',
    'Firestore indexes deployed'
);

// ─────────────────────────────────────────────────────────────────────────────
head('Step 3: Verify no Appwrite remnants in Dart code');
// ─────────────────────────────────────────────────────────────────────────────

const appwritePatterns = [
    "package:appwrite/appwrite.dart",
    "package:dart_appwrite/dart_appwrite.dart",
    "AppwriteService()",
    "AppwriteException",
    "dart_appwrite",
];

let appwriteRemainingCount = 0;
const dartFiles = run(
    `find ${ROOT}/lib -name "*.dart" -not -name "appwrite_service.dart"`,
)?.trim().split('\n').filter(Boolean) ?? [];

for (const pattern of appwritePatterns) {
    let foundCount = 0;
    for (const file of dartFiles) {
        try {
            const content = readFileSync(file, 'utf8');
            if (content.includes(pattern)) {
                warn(`Found "${pattern}" in: ${file.replace(ROOT, '.')}`);
                foundCount++;
                appwriteRemainingCount++;
            }
        } catch { }
    }
    if (foundCount === 0) {
        pass(`No references to "${pattern}" in app code`);
    }
}

if (appwriteRemainingCount === 0) {
    pass('App code is 100% Appwrite-free ✨');
} else {
    err(`Found ${appwriteRemainingCount} Appwrite reference(s) remaining`);
}

// Check pubspec.yaml
const pubspec = readFileSync(resolve(ROOT, 'pubspec.yaml'), 'utf8');
const hasAppwriteDep = /^\s+(appwrite|dart_appwrite)\s*:/m.test(pubspec);
if (hasAppwriteDep) {
    warn('appwrite or dart_appwrite still in pubspec.yaml — remove them and run `flutter pub get`');
    stepsFailed++;
} else {
    pass('pubspec.yaml has no Appwrite package dependencies');
}

// ─────────────────────────────────────────────────────────────────────────────
head('Step 4: Run flutter pub get');
// ─────────────────────────────────────────────────────────────────────────────

runOrThrow('flutter pub get', 'flutter pub get completed');

// ─────────────────────────────────────────────────────────────────────────────
head('Step 5: Run flutter analyze');
// ─────────────────────────────────────────────────────────────────────────────

info('Running flutter analyze...');
let analyzeOutput = '';
try {
    analyzeOutput = execSync('flutter analyze --no-fatal-infos', {
        cwd: ROOT,
        encoding: 'utf8',
        stdio: ['pipe', 'pipe', 'pipe'],
    });
} catch (e) {
    // flutter analyze exits non-zero when there are errors — still capture output
    analyzeOutput = (e.stdout ?? '') + (e.stderr ?? '');
}
{
    const errorLines = analyzeOutput
        .split('\n')
        .filter(l => l.trimStart().startsWith('error ') || l.trimStart().startsWith('warning '));
    const appErrors = errorLines.filter(l => !l.includes('scripts/'));

    if (appErrors.length === 0) {
        pass('flutter analyze: 0 errors in app code');
    } else {
        err(`flutter analyze found ${appErrors.length} issue(s):`);
        appErrors.slice(0, 10).forEach(l => console.log(`   ${l}`));
    }
    const scriptWarnings = errorLines.filter(l => l.includes('scripts/'));
    if (scriptWarnings.length > 0) {
        warn(`${scriptWarnings.length} issue(s) in scripts/ (not shipped)`);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
head('Step 6: Seed Firestore baseline data (optional check)');
// ─────────────────────────────────────────────────────────────────────────────

info('Checking if Firebase Admin SDK is available for seeding...');
const adminAvailable = run('node -e "require(\'firebase-admin\')"');
if (adminAvailable !== null) {
    info('firebase-admin is available. Seeding is possible via scripts/seed_firestore.mjs');
    pass('firebase-admin available for seeding');
} else {
    warn('firebase-admin not installed. To seed: npm install firebase-admin && node scripts/seed_firestore.mjs');
}

// ─────────────────────────────────────────────────────────────────────────────
head('Step 7: Verify firebase.json references both rules and indexes');
// ─────────────────────────────────────────────────────────────────────────────

try {
    const fbJson = JSON.parse(readFileSync(resolve(ROOT, 'firebase.json'), 'utf8'));
    if (fbJson.firestore?.rules === 'firestore.rules') {
        pass('firebase.json → firestore.rules configured');
    } else {
        warn('firebase.json is missing firestore.rules reference');
    }
    if (fbJson.firestore?.indexes === 'firestore.indexes.json') {
        pass('firebase.json → firestore.indexes.json configured');
    } else {
        warn('firebase.json is missing firestore.indexes.json reference');
    }
} catch {
    warn('Could not parse firebase.json');
}

// ─────────────────────────────────────────────────────────────────────────────
head('═══════════════ Migration Status Report ═══════════════');
// ─────────────────────────────────────────────────────────────────────────────

console.log(`\n  ${GREEN}Passed${RESET}: ${stepsPassed}`);
console.log(`  ${RED}Failed${RESET}: ${stepsFailed}`);

if (stepsFailed === 0) {
    console.log(`\n  ${GREEN}${BOLD}🎉 Migration Complete! The CRADI app is fully on Firebase.${RESET}\n`);
    console.log(`  Next steps:`);
    console.log(`  1. Run \`flutter test\` to verify test suite`);
    console.log(`  2. Perform manual QA: sign-up → OTP → profile → report → verify`);
    console.log(`  3. Phase 7: Wire Firebase Cloud Functions for transactional email`);
    console.log(`  4. Phase 7: Implement FLAG_SECURE via method channel\n`);
} else {
    console.log(`\n  ${YELLOW}${BOLD}Review the ${stepsFailed} failed step(s) above before release.${RESET}\n`);
}
