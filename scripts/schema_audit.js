#!/usr/bin/env node
/**
 * ═══════════════════════════════════════════════════════════════════════════════
 *  CRADI / EWER — Firestore Schema Audit & Repair Script
 * ═══════════════════════════════════════════════════════════════════════════════
 *
 *  Purpose:  Scans all Firestore documents in key collections, compares each
 *            document against the canonical schema defined by the Flutter app,
 *            and backfills any missing properties with safe defaults.
 *
 *  Usage:
 *    1. Place your Firebase service account JSON at ./serviceAccountKey.json
 *       (or set GOOGLE_APPLICATION_CREDENTIALS env var)
 *    2. Run:
 *         node scripts/schema_audit.js              # Dry-run (report only)
 *         node scripts/schema_audit.js --fix        # Apply fixes
 *         node scripts/schema_audit.js --fix --collection users  # Fix one collection
 *
 *  Safety:
 *    - Default mode is DRY-RUN — nothing is written.
 *    - Missing fields are backfilled with safe, non-destructive defaults.
 *    - Existing fields are NEVER overwritten.
 *    - All actions are logged with document IDs.
 * ═══════════════════════════════════════════════════════════════════════════════
 */

const admin = require('firebase-admin');
const path = require('path');
const fs = require('fs');

// ─────────────────────────── CONFIG ───────────────────────────────────────────

const PROJECT_ID = 'ewer-8f788';

// Try multiple paths for the service account key
const SA_PATHS = [
  process.env.GOOGLE_APPLICATION_CREDENTIALS,
  path.join(__dirname, 'serviceAccountKey.json'),
  path.join(__dirname, 'service-account-key.json'),
  path.join(__dirname, '..', 'serviceAccountKey.json'),
  path.join(process.env.HOME || '', `${PROJECT_ID}-firebase-adminsdk.json`),
].filter(Boolean);

let credential;
for (const saPath of SA_PATHS) {
  if (fs.existsSync(saPath)) {
    credential = admin.credential.cert(require(saPath));
    console.log(`✅ Using service account: ${saPath}`);
    break;
  }
}

if (!credential) {
  console.error('❌ No service account key found. Tried:');
  SA_PATHS.forEach(p => console.error(`   - ${p}`));
  console.error('\nPlace your key at scripts/serviceAccountKey.json or set GOOGLE_APPLICATION_CREDENTIALS');
  process.exit(1);
}

admin.initializeApp({ credential, projectId: PROJECT_ID });
const db = admin.firestore();

// ─────────────────────────── CANONICAL SCHEMAS ───────────────────────────────
// These match exactly what the Flutter app writes when creating documents.
// Each entry: { field: defaultValue }
// null = no default (field is expected but won't be backfilled)

const SCHEMAS = {
  users: {
    name:              '',
    email:             '',
    phone:             '',
    role:              'user',
    address:           '',
    state:             '',
    lga:               '',
    ward:              '',
    isVerified:        false,
    isApproved:        false,
    biometricsEnabled: false,
    profileImageUrl:   '',
    monitoringZone:    null,      // Optional — won't backfill
    registrationCode:  null,      // Optional — won't backfill
    fcmToken:          null,      // Optional — won't backfill
    createdAt:         null,      // Should exist from createDocument
    updatedAt:         null,      // Should exist from createDocument
    lastLoginAt:       null,      // Optional — won't backfill
  },

  reports: {
    userId:            '',
    hazardType:        '',
    severity:          '',
    latitude:          null,      // Required but can't invent GPS coords
    longitude:         null,
    locationDetails:   '',
    location:          '',
    address:           '',
    ward:              '',
    lga:               '',
    state:             '',
    description:       '',
    submittedAt:       null,
    imageUrls:         [],
    status:            'pending',
    isAlert:           false,
    verificationCount: 0,
    createdAt:         null,
    updatedAt:         null,
  },

  verifications: {
    reportId:      '',
    verifierId:    '',
    verifierName:  '',
    verifierWard:  '',
    status:        'pending',    // pending | confirmed | denied
    confirmedAt:   null,
    createdAt:     null,
    updatedAt:     null,
  },

  alerts: {
    reportId:    '',
    hazardType:  '',
    severity:    '',
    ward:        '',
    lga:         '',
    state:       '',
    status:      'active',
    isAlert:     true,
    createdAt:   null,
    updatedAt:   null,
  },

  contacts: {
    userId:      '',
    name:        '',
    phone:       '',
    relationship:'',
    priority:    0,
    createdAt:   null,
    updatedAt:   null,
  },

  knowledge_base: {
    title:       '',
    content:     '',
    category:    '',
    tags:        [],
    createdAt:   null,
    updatedAt:   null,
  },

  chats: {
    participants: [],
    lastMessage:  '',
    lastMessageAt: null,
    createdAt:    null,
    updatedAt:    null,
  },

  messages: {
    chatId:    '',
    senderId:  '',
    text:      '',
    createdAt: null,
  },

  login_history: {
    userId:            '',
    deviceFingerprint: '',
    deviceName:        '',
    success:           false,
    riskScore:         null,      // Fraud detection score
    timestamp:         null,      // Login timestamp
    createdAt:         null,
    updatedAt:         null,
  },

  trusted_devices: {
    userId:            '',
    deviceFingerprint: '',
    deviceName:        '',
    trusted:           true,
    lastUsed:          null,      // Last time device was used
    createdAt:         null,
    updatedAt:         null,
  },
};

// ─────────────────────────── CLI ARGS ─────────────────────────────────────────

const args = process.argv.slice(2);
const DRY_RUN = !args.includes('--fix');
const targetCollection = (() => {
  const idx = args.indexOf('--collection');
  return idx !== -1 ? args[idx + 1] : null;
})();

// ─────────────────────────── AUDIT LOGIC ─────────────────────────────────────

async function auditCollection(collectionName, schema) {
  const colRef = db.collection(collectionName);
  const snapshot = await colRef.get();

  if (snapshot.empty) {
    console.log(`  📭 ${collectionName}: empty collection — skipped`);
    return { collection: collectionName, total: 0, issues: 0, fixed: 0 };
  }

  let issueCount = 0;
  let fixedCount = 0;
  const schemaFields = Object.keys(schema);

  console.log(`\n  📋 ${collectionName}: ${snapshot.size} documents`);
  console.log(`     Expected fields: ${schemaFields.join(', ')}`);
  console.log('     ─────────────────────────────────────────────');

  for (const doc of snapshot.docs) {
    const data = doc.data();
    const missing = [];
    const patch = {};

    for (const field of schemaFields) {
      if (!(field in data)) {
        missing.push(field);
        const defaultVal = schema[field];
        if (defaultVal !== null) {
          patch[field] = defaultVal;
        }
      }
    }

    // Also detect extra/unexpected fields (informational only)
    const extra = Object.keys(data).filter(
      k => !schemaFields.includes(k) && k !== '$id' && k !== '$snapshot'
    );

    if (missing.length > 0 || extra.length > 0) {
      issueCount++;
      console.log(`\n     📄 ${doc.id}:`);

      if (missing.length > 0) {
        console.log(`        ❌ Missing: ${missing.join(', ')}`);
      }
      if (extra.length > 0) {
        console.log(`        ℹ️  Extra:   ${extra.join(', ')}`);
      }

      if (Object.keys(patch).length > 0) {
        if (DRY_RUN) {
          console.log(`        🔧 Would patch: ${JSON.stringify(patch)}`);
        } else {
          try {
            await doc.ref.update(patch);
            fixedCount++;
            console.log(`        ✅ Patched: ${Object.keys(patch).join(', ')}`);
          } catch (err) {
            console.log(`        ❌ Patch failed: ${err.message}`);
          }
        }
      }
    }
  }

  if (issueCount === 0) {
    console.log('     ✅ All documents match schema');
  } else {
    console.log(`\n     📊 ${issueCount}/${snapshot.size} documents have issues`);
    if (!DRY_RUN) {
      console.log(`     ✅ Fixed: ${fixedCount} documents`);
    }
  }

  return { collection: collectionName, total: snapshot.size, issues: issueCount, fixed: fixedCount };
}

// ─────────────────────────── MAIN ────────────────────────────────────────────

async function main() {
  console.log('═══════════════════════════════════════════════════════════════');
  console.log('  CRADI/EWER Firestore Schema Audit');
  console.log(`  Project: ${PROJECT_ID}`);
  console.log(`  Mode: ${DRY_RUN ? '🔍 DRY-RUN (report only)' : '🔧 FIX (applying patches)'}`);
  if (targetCollection) {
    console.log(`  Target: ${targetCollection} only`);
  }
  console.log(`  Time: ${new Date().toISOString()}`);
  console.log('═══════════════════════════════════════════════════════════════');

  const collections = targetCollection
    ? { [targetCollection]: SCHEMAS[targetCollection] }
    : SCHEMAS;

  if (targetCollection && !SCHEMAS[targetCollection]) {
    console.error(`\n❌ Unknown collection: "${targetCollection}"`);
    console.error(`   Available: ${Object.keys(SCHEMAS).join(', ')}`);
    process.exit(1);
  }

  const results = [];

  for (const [name, schema] of Object.entries(collections)) {
    try {
      const result = await auditCollection(name, schema);
      results.push(result);
    } catch (err) {
      console.error(`\n  ❌ Error auditing ${name}: ${err.message}`);
      results.push({ collection: name, total: 0, issues: -1, fixed: 0, error: err.message });
    }
  }

  // ─── Summary Table ─────────────────────────────────────────────────────────
  console.log('\n═══════════════════════════════════════════════════════════════');
  console.log('  SUMMARY');
  console.log('═══════════════════════════════════════════════════════════════');
  console.log('');
  console.log('  Collection          | Docs  | Issues | Fixed');
  console.log('  ─────────────────────────────────────────────');

  let totalDocs = 0, totalIssues = 0, totalFixed = 0;
  for (const r of results) {
    const name = r.collection.padEnd(20);
    const docs = String(r.total).padStart(5);
    const issues = r.issues === -1 ? 'ERROR' : String(r.issues).padStart(6);
    const fixed = String(r.fixed).padStart(5);
    console.log(`  ${name}| ${docs} | ${issues} | ${fixed}`);
    totalDocs += r.total;
    if (r.issues > 0) totalIssues += r.issues;
    totalFixed += r.fixed;
  }

  console.log('  ─────────────────────────────────────────────');
  console.log(`  ${'TOTAL'.padEnd(20)}| ${String(totalDocs).padStart(5)} | ${String(totalIssues).padStart(6)} | ${String(totalFixed).padStart(5)}`);
  console.log('');

  if (DRY_RUN && totalIssues > 0) {
    console.log('  💡 Run with --fix to apply patches:');
    console.log('     node scripts/schema_audit.js --fix');
    console.log('');
  }

  if (totalIssues === 0) {
    console.log('  🎉 All documents match their expected schema!');
    console.log('');
  }

  process.exit(0);
}

main().catch(err => {
  console.error('Fatal error:', err);
  process.exit(1);
});
