/**
 * CRADI — Verification Request Cloud Function (Firebase Admin SDK)
 *
 * Trigger: Firestore onDocumentCreated('reports/{reportId}')
 *          fires when a new report is submitted.
 *
 * Behaviour:
 *   1. Reads the new report's ward and LGA.
 *   2. Looks up EWM (Early Warning Monitor) users in the same ward, excluding the reporter.
 *   3. Sends an FCM push notification to each EWM's device token.
 *   4. If no peers are found, logs the event (escalation is handled separately).
 */

'use strict';

const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');

if (!getApps().length) initializeApp();
const db = getFirestore();
const messaging = getMessaging();

// ─────────────────────────────────────────────────────────────────────────────
// Cloud Function: sendVerificationRequestOnCreate
// ─────────────────────────────────────────────────────────────────────────────
exports.sendVerificationRequestOnCreate = onDocumentCreated(
    { document: 'reports/{reportId}', region: 'us-central1' },
    async (event) => {
        const report = event.data.data();
        const reportId = event.params.reportId;

        const { ward, lga, userId: reporterId, hazardType } = report;

        console.log(
            `[sendVerificationRequestOnCreate] New report ${reportId}: ward=${ward}, lga=${lga}, reporter=${reporterId}`,
        );

        // ── Find EWM peers in the same ward ───────────────────────────────────
        const peersSnap = await db
            .collection('users')
            .where('role', '==', 'ewm')
            .where('ward', '==', ward)
            .where('lga', '==', lga)
            .limit(50)
            .get();

        // Exclude the reporter themselves
        const peerTokens = peersSnap.docs
            .filter(doc => doc.id !== reporterId)
            .map(doc => doc.data().fcmToken)
            .filter(Boolean);

        console.log(
            `[sendVerificationRequestOnCreate] Found ${peersSnap.size} peers, ${peerTokens.length} with FCM tokens`,
        );

        if (peerTokens.length === 0) {
            console.log(
                '[sendVerificationRequestOnCreate] No peer tokens — skipping FCM send. ' +
                'Escalation will be handled by processEscalations.',
            );
            return;
        }

        // ── Send multicast FCM ────────────────────────────────────────────────
        const response = await messaging.sendEachForMulticast({
            tokens: peerTokens,
            notification: {
                title: '📋 Verification Request',
                body: `A ${hazardType || 'hazard'} report in ${ward}, ${lga} needs your verification.`,
            },
            data: {
                type: 'verification_request',
                reportId,
                ward: ward || '',
                lga: lga || '',
            },
            android: {
                priority: 'high',
                notification: { channelId: 'alerts_channel', priority: 'max', defaultSound: true },
            },
            apns: {
                payload: {
                    aps: {
                        alert: {
                            title: '📋 Verification Request',
                            body: `A ${hazardType || 'hazard'} report in ${ward}, ${lga} needs your verification.`,
                        },
                        sound: 'default',
                        badge: 1,
                    },
                },
            },
        });

        console.log(
            `[sendVerificationRequestOnCreate] FCM result — success: ${response.successCount}, failed: ${response.failureCount}`,
        );
    },
);
