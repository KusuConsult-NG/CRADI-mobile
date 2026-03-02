/**
 * CRADI — Escalation Timer Cloud Function (Firebase Admin SDK)
 *
 * Schedule: every 5 minutes
 *
 * Behaviour:
 * 1. Queries Firestore 'reports' for documents where:
 * - status == 'pending'
        * - submittedAt < now - 30 minutes
            * 2. For each such report:
 * a.Updates its status to 'escalated' with a reason + timestamp.
 * b.Reads ldp_coordinator and project_staff users in the same LGA.
 * c.Sends an FCM push to each coordinator / staff FCM token.
 *
 * Note: only 100 reports are processed per invocation to keep execution
    * time well under the 9 - minute Cloud Functions v2 timeout.
 */

'use strict';

const { onSchedule } = require('firebase-functions/v2/scheduler');
const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');

if (!getApps().length) initializeApp();
const db = getFirestore();
const messaging = getMessaging();

// ─────────────────────────────────────────────────────────────────────────────
// Helper: send FCM multicast (silently ignores empty token lists)
// ─────────────────────────────────────────────────────────────────────────────
async function sendFcmToTokens(tokens, notification, data = {}) {
    if (!tokens || tokens.length === 0) return;

    const result = await messaging.sendEachForMulticast({
        tokens,
        notification,
        data: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v)])),
        android: {
            priority: 'high',
            notification: { channelId: 'alerts_channel', priority: 'max', defaultSound: true },
        },
        apns: {
            payload: { aps: { alert: notification, sound: 'default', badge: 1 } },
        },
    });

    console.log(
        `[escalationTimer] FCM — success: ${result.successCount}, failed: ${result.failureCount}`,
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// Cloud Function: escalationTimer
// ─────────────────────────────────────────────────────────────────────────────
exports.escalationTimer = onSchedule(
    { schedule: 'every 5 minutes', region: 'us-central1', timeoutSeconds: 540 },
    async (_context) => {
        console.log('[escalationTimer] Starting scheduled escalation check...');

        const thirtyMinutesAgo = new Date(Date.now() - 30 * 60 * 1000);

        // ── Fetch pending reports older than 30 minutes ───────────────────────
        const snap = await db
            .collection('reports')
            .where('status', '==', 'pending')
            .where('submittedAt', '<', thirtyMinutesAgo)
            .limit(100)
            .get();

        console.log(`[escalationTimer] ${snap.size} report(s) to escalate.`);
        if (snap.empty) return;

        const batch = db.batch();

        // Group reports by LGA so we can do one coordinator lookup per LGA
        const lgaMap = new Map();
        for (const doc of snap.docs) {
            const lga = doc.data().lga || '';
            if (!lgaMap.has(lga)) lgaMap.set(lga, []);
            lgaMap.get(lga).push(doc);

            // Mark escalated in the batch
            batch.update(doc.ref, {
                status: 'escalated',
                escalatedAt: FieldValue.serverTimestamp(),
                escalationReason: 'Auto-escalation: No peer verification within 30 minutes',
            });
        }

        // Commit status updates
        await batch.commit();
        console.log(`[escalationTimer] Marked ${snap.size} report(s) as escalated.`);

        // ── Notify coordinators per LGA ───────────────────────────────────────
        for (const [lga, reports] of lgaMap.entries()) {
            const [coordSnap, staffSnap] = await Promise.all([
                db.collection('users')
                    .where('role', '==', 'ldp_coordinator')
                    .where('lga', '==', lga)
                    .limit(20)
                    .get(),
                db.collection('users')
                    .where('role', '==', 'project_staff')
                    .limit(20)
                    .get(),
            ]);

            const tokens = [...coordSnap.docs, ...staffSnap.docs]
                .map(d => d.data().fcmToken)
                .filter(Boolean);

            if (tokens.length === 0) {
                console.log(`[escalationTimer] No coordinator/staff tokens for LGA: ${lga}`);
                continue;
            }

            const reportCount = reports.length;
            await sendFcmToTokens(
                tokens,
                {
                    title: '⏰ Unverified Reports Escalated',
                    body: `${reportCount} hazard report${reportCount > 1 ? 's' : ''} in ${lga || 'your area'} passed the 30-minute verification window.`,
                },
                { type: 'escalation_auto', lga },
            );

            console.log(
                `[escalationTimer] Notified ${tokens.length} coordinator(s)/staff for LGA: ${lga}`,
            );
        }

        console.log('[escalationTimer] Done.');
    },
);
