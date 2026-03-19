#!/usr/bin/env node
/**
 * migrate_report_statuses.js
 * 
 * One-time Firestore migration script for the CRADI reports collection.
 * Updates old status strings to the new standardised values:
 *
 *   acknowledged  →  verified
 *   validated      →  approved
 *   resolved       →  approved
 *   escalated      →  pending  (+ sets escalated: true flag)
 *
 * Usage:
 *   cd firebase-functions
 *   node migrate_report_statuses.js              # Dry run (default)
 *   node migrate_report_statuses.js --apply      # Apply changes
 *
 * The script uses batched writes (max 500 per batch) for efficiency
 * and prints a summary of all changes made.
 */

const admin = require("firebase-admin");

// ── Initialise Firebase Admin ────────────────────────────────────────────────
// Uses Application Default Credentials when running locally with
// `firebase login` or GOOGLE_APPLICATION_CREDENTIALS env var.
if (!admin.apps.length) {
  admin.initializeApp({
    projectId: "ewer-8f788",
  });
}

const db = admin.firestore();
const COLLECTION = "reports";
const BATCH_SIZE = 500;

// ── Status mapping ───────────────────────────────────────────────────────────
const STATUS_MAP = {
  acknowledged: "verified",
  validated: "approved",
  resolved: "approved",
  escalated: "__escalated__", // special case handled below
};

// ── Main ─────────────────────────────────────────────────────────────────────
async function migrate() {
  const dryRun = !process.argv.includes("--apply");

  if (dryRun) {
    console.log("═══════════════════════════════════════════════════════════");
    console.log("  DRY RUN — no changes will be written to Firestore.");
    console.log("  Pass --apply to execute the migration.");
    console.log("═══════════════════════════════════════════════════════════\n");
  } else {
    console.log("═══════════════════════════════════════════════════════════");
    console.log("  LIVE RUN — changes WILL be written to Firestore.");
    console.log("═══════════════════════════════════════════════════════════\n");
  }

  const oldStatuses = Object.keys(STATUS_MAP);

  // Query all reports that have one of the old statuses
  let totalUpdated = 0;
  const summary = {
    acknowledged: 0,
    validated: 0,
    resolved: 0,
    escalated: 0,
  };

  for (const oldStatus of oldStatuses) {
    console.log(`\n── Scanning for status: "${oldStatus}" ──`);

    const snapshot = await db
      .collection(COLLECTION)
      .where("status", "==", oldStatus)
      .get();

    if (snapshot.empty) {
      console.log(`   No documents found with status "${oldStatus}".`);
      continue;
    }

    console.log(`   Found ${snapshot.size} document(s) with status "${oldStatus}".`);

    // Process in batches of BATCH_SIZE
    const docs = snapshot.docs;
    for (let i = 0; i < docs.length; i += BATCH_SIZE) {
      const batchDocs = docs.slice(i, i + BATCH_SIZE);
      const batch = db.batch();

      for (const doc of batchDocs) {
        const data = doc.data();
        let updateData;

        if (oldStatus === "escalated") {
          // Escalated: keep report as pending, add escalated boolean flag
          updateData = {
            status: "pending",
            escalated: true,
            migratedFrom: "escalated",
            migratedAt: admin.firestore.FieldValue.serverTimestamp(),
          };
        } else {
          const newStatus = STATUS_MAP[oldStatus];
          updateData = {
            status: newStatus,
            migratedFrom: oldStatus,
            migratedAt: admin.firestore.FieldValue.serverTimestamp(),
          };
        }

        console.log(
          `   [${dryRun ? "DRY" : "UPD"}] ${doc.id}: ` +
            `"${data.status}" → "${updateData.status}"` +
            (oldStatus === "escalated" ? " + escalated:true" : "")
        );

        if (!dryRun) {
          batch.update(doc.ref, updateData);
        }

        summary[oldStatus]++;
        totalUpdated++;
      }

      if (!dryRun) {
        await batch.commit();
        console.log(`   ✓ Committed batch of ${batchDocs.length} updates.`);
      }
    }
  }

  // ── Summary ──────────────────────────────────────────────────────────────
  console.log("\n═══════════════════════════════════════════════════════════");
  console.log("  MIGRATION SUMMARY");
  console.log("═══════════════════════════════════════════════════════════");
  console.log(`  Mode:         ${dryRun ? "DRY RUN" : "APPLIED"}`);
  console.log(`  Total updated: ${totalUpdated}`);
  console.log("  ─────────────────────────────────────────────────────────");
  console.log(`  acknowledged → verified:    ${summary.acknowledged}`);
  console.log(`  validated    → approved:    ${summary.validated}`);
  console.log(`  resolved     → approved:    ${summary.resolved}`);
  console.log(`  escalated    → pending+flag: ${summary.escalated}`);
  console.log("═══════════════════════════════════════════════════════════\n");

  if (dryRun && totalUpdated > 0) {
    console.log("  ⚠  Run with --apply to execute these changes.\n");
  }

  if (totalUpdated === 0) {
    console.log("  ✅ No documents need migration — database is clean.\n");
  }
}

// ── Run ──────────────────────────────────────────────────────────────────────
migrate()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error("Migration failed:", err);
    process.exit(1);
  });
