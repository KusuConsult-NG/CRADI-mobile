#!/usr/bin/env node
/**
 * Firestore Schema Fix Script
 * ============================
 * Fixes `status: "escalated"` → `status: "pending"` + `escalated: true`
 *
 * Usage:
 *   node scripts/fix_firestore_schema.js [--dry-run]
 */

const admin = require('firebase-admin');
const path = require('path');

// ── Configuration ──────────────────────────────────────────────────────────
const PROJECT_ID = 'ewer-8f788';
const DRY_RUN = process.argv.includes('--dry-run');

// Use explicit service account key for proper write auth
const serviceAccountPath = path.join(__dirname, 'service-account-key.json');
let serviceAccount;
try {
  serviceAccount = require(serviceAccountPath);
  console.log(`Using service account: ${serviceAccount.client_email}`);
} catch {
  console.log('No service-account-key.json found, using application default credentials');
  serviceAccount = null;
}

// ── Initialise Firebase Admin ──────────────────────────────────────────────
if (serviceAccount) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    projectId: PROJECT_ID,
  });
} else {
  admin.initializeApp({ projectId: PROJECT_ID });
}
const db = admin.firestore();

// Valid statuses
const VALID_STATUSES = ['pending', 'verified', 'approved', 'rejected'];

// Status mapping
const STATUS_MIGRATION_MAP = {
  escalated: 'pending',
  acknowledged: 'verified',
  validated: 'verified',
  resolved: 'approved',
};

async function fixReportsSchema() {
  console.log('╔══════════════════════════════════════════════════════╗');
  console.log('║  CRADI Firestore Schema Fix                        ║');
  console.log(`║  Project: ${PROJECT_ID.padEnd(42)}║`);
  console.log(`║  Mode: ${DRY_RUN ? 'DRY RUN (no writes)' : '🔴 LIVE (writing changes)'}${DRY_RUN ? '              ' : '         '}║`);
  console.log('╚══════════════════════════════════════════════════════╝\n');

  const reportsRef = db.collection('reports');
  const snapshot = await reportsRef.get();

  console.log(`Found ${snapshot.size} reports in total.\n`);

  let fixedCount = 0;
  let errorCount = 0;
  let verifiedCount = 0;

  for (const doc of snapshot.docs) {
    const data = doc.data();
    const docId = doc.id;
    const currentStatus = (data.status || '').toString().toLowerCase();

    if (VALID_STATUSES.includes(currentStatus)) {
      console.log(`  ✓ ${docId}: status="${data.status}" — OK`);
      continue;
    }

    const newStatus = STATUS_MIGRATION_MAP[currentStatus] || 'pending';
    const updates = { status: newStatus };
    if (currentStatus === 'escalated') {
      updates.escalated = true;
    }

    console.log(`  📄 ${docId}: "${data.status}" → "${newStatus}"`);

    if (!DRY_RUN) {
      try {
        // Write the update
        await reportsRef.doc(docId).update(updates);
        
        // READ BACK to verify the write persisted
        const verifyDoc = await reportsRef.doc(docId).get();
        const verifiedData = verifyDoc.data();
        
        if (verifiedData.status === newStatus) {
          console.log(`     ✅ Verified: status is now "${verifiedData.status}"`);
          verifiedCount++;
        } else {
          console.log(`     ❌ WRITE FAILED: status is still "${verifiedData.status}"`);
          errorCount++;
        }
        
        fixedCount++;
      } catch (err) {
        console.error(`     ❌ Error: ${err.message}`);
        errorCount++;
      }
    } else {
      fixedCount++;
    }
  }

  console.log('\n───── SUMMARY ─────');
  console.log(`  Total reports: ${snapshot.size}`);
  console.log(`  Fixed: ${fixedCount}`);
  console.log(`  Verified: ${verifiedCount}`);
  console.log(`  Errors: ${errorCount}`);

  if (DRY_RUN) {
    console.log('\n  ℹ️  DRY RUN — no changes written.');
  } else if (errorCount === 0) {
    console.log('\n  ✅ All fixes applied and verified.');
  } else {
    console.log('\n  ⚠️  Some writes failed. Check errors above.');
  }
}

fixReportsSchema()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('Fatal error:', err);
    process.exit(1);
  });
