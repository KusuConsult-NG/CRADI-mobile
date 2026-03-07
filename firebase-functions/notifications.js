/**
 * Firebase Cloud Functions — CRADI Mobile FCM Peer Notification Pipeline
 *
 * Functions (all HTTPS callable from Flutter via cloud_functions package):
 *   1. sendVerificationRequest     — sends FCM to peer EWMs in same ward
 *   2. sendEscalationNotification  — sends FCM to coordinators/staff
 *   3. sendReporterStatusUpdate    — sends FCM to original reporter
 *
 * Firestore trigger functions:
 *   4. processEscalations          — onCreate on scheduled_escalations/{docId}
 *   5. distributeValidatedAlert    — onUpdate on reports/{reportId} → status=validated
 */

'use strict';

const admin = require('firebase-admin');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onDocumentCreated, onDocumentUpdated } = require('firebase-functions/v2/firestore');

if (admin.apps.length === 0) {
    admin.initializeApp();
}

const db = admin.firestore();
const messaging = admin.messaging();

// ─────────────────────────────────────────────────────────────────────────────
// Helper: Send FCM to multiple device tokens
// ─────────────────────────────────────────────────────────────────────────────

async function sendFcmToTokens(tokens, notification, data = {}) {
    if (!tokens || tokens.length === 0) return { successCount: 0, failureCount: 0 };

    const message = {
        tokens,
        notification: { title: notification.title, body: notification.body },
        data: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v)])),
        android: {
            priority: 'high',
            notification: { channelId: 'alerts_channel', priority: 'max', defaultSound: true },
        },
        apns: {
            payload: { aps: { alert: { title: notification.title, body: notification.body }, sound: 'default', badge: 1 } },
        },
    };

    const response = await messaging.sendEachForMulticast(message);
    return { successCount: response.successCount, failureCount: response.failureCount };
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. sendVerificationRequest — HTTPS Callable
//    Input: { reportId, ward, lga, reporterId, peerTokens[] }
// ─────────────────────────────────────────────────────────────────────────────

exports.sendVerificationRequest = onCall({ region: 'us-central1' }, async (request) => {
    const { reportId, ward, lga, reporterId, peerTokens } = request.data;

    if (!reportId || !peerTokens || peerTokens.length === 0) {
        throw new HttpsError('invalid-argument', 'reportId and peerTokens are required');
    }

    const reportDoc = await db.collection('reports').doc(reportId).get();
    if (!reportDoc.exists) throw new HttpsError('not-found', `Report ${reportId} not found`);
    if (reportDoc.data().status !== 'pending') {
        return { success: true, message: 'Report no longer pending, skipping' };
    }

    const result = await sendFcmToTokens(
        peerTokens,
        { title: '📋 Verification Request', body: `A hazard report in ${ward}, ${lga} needs your verification.` },
        { type: 'verification_request', reportId, ward, lga }
    );

    console.log(`sendVerificationRequest: ${result.successCount}/${peerTokens.length} for report ${reportId}`);
    return { success: true, ...result };
});

// ─────────────────────────────────────────────────────────────────────────────
// 2. sendEscalationNotification — HTTPS Callable
//    Input: { reportId, reason, recipientTokens[] }
// ─────────────────────────────────────────────────────────────────────────────

exports.sendEscalationNotification = onCall({ region: 'us-central1' }, async (request) => {
    const { reportId, reason, recipientTokens } = request.data;

    if (!reportId || !recipientTokens || recipientTokens.length === 0) {
        throw new HttpsError('invalid-argument', 'reportId and recipientTokens are required');
    }

    const reportDoc = await db.collection('reports').doc(reportId).get();
    const hazardType = reportDoc.exists ? (reportDoc.data().hazardType || 'Hazard') : 'Hazard';
    const lga = reportDoc.exists ? (reportDoc.data().lga || '') : '';

    const result = await sendFcmToTokens(
        recipientTokens,
        {
            title: '⚠️ Report Escalated',
            body: `${hazardType} report${lga ? ` in ${lga}` : ''} needs coordinator review. Reason: ${reason}`,
        },
        { type: 'escalation', reportId, reason }
    );

    console.log(`sendEscalationNotification: ${result.successCount}/${recipientTokens.length} for report ${reportId}`);
    return { success: true, ...result };
});

// ─────────────────────────────────────────────────────────────────────────────
// 3. sendReporterStatusUpdate — HTTPS Callable
//    Input: { reporterToken, reportId, status, reason? }
// ─────────────────────────────────────────────────────────────────────────────

exports.sendReporterStatusUpdate = onCall({ region: 'us-central1' }, async (request) => {
    const { reporterToken, reportId, status, reason } = request.data;

    if (!reporterToken || !reportId || !status) {
        throw new HttpsError('invalid-argument', 'reporterToken, reportId, and status are required');
    }

    const statusMessages = {
        validated: '✅ Your report has been verified and an alert has been issued.',
        escalated: '📢 Your report has been escalated to a coordinator.',
        rejected: `❌ Your report was not validated.${reason ? ` Reason: ${reason}` : ''}`,
        pending: '⏳ Your report is awaiting peer verification.',
    };

    const result = await sendFcmToTokens(
        [reporterToken],
        { title: '📬 Report Update', body: statusMessages[status] || `Status: ${status}` },
        { type: 'report_status', reportId, status }
    );

    console.log(`sendReporterStatusUpdate: status=${status} for report ${reportId}`);
    return { success: true, ...result };
});

// ─────────────────────────────────────────────────────────────────────────────
// 4. processEscalations — Firestore onCreate Trigger
//    Fires when a doc is created in 'scheduled_escalations/{docId}'
//    Input doc: { reportId, escalateAt (Timestamp), status: 'pending' }
// ─────────────────────────────────────────────────────────────────────────────

exports.processEscalations = onDocumentCreated(
    { document: 'scheduled_escalations/{docId}', region: 'us-central1' },
    async (event) => {
        const data = event.data.data();
        const { reportId, escalateAt } = data;
        if (!reportId || !escalateAt) return;

        // Wait until escalation time
        const delayMs = Math.max(0, escalateAt.toMillis() - Date.now());
        if (delayMs > 0) await new Promise(resolve => setTimeout(resolve, delayMs));

        // Re-check — report may already be verified
        const reportDoc = await db.collection('reports').doc(reportId).get();
        if (!reportDoc.exists || reportDoc.data().status !== 'pending') {
            await event.data.ref.update({ status: 'skipped', reason: `Status: ${reportDoc.data()?.status ?? 'not found'}` });
            return;
        }

        const lga = reportDoc.data().lga || '';
        const [coordSnap, staffSnap] = await Promise.all([
            db.collection('users').where('role', '==', 'ewr').where('lga', '==', lga).limit(20).get(),
            db.collection('users').where('role', '==', 'ewv').limit(20).get(),
        ]);

        const tokens = [...coordSnap.docs, ...staffSnap.docs]
            .map(d => d.data().fcmToken).filter(t => t);

        if (tokens.length > 0) {
            await sendFcmToTokens(
                tokens,
                { title: '⏰ Unverified Report Escalated', body: `A hazard report in ${lga} has not been verified in 30 minutes.` },
                { type: 'escalation_auto', reportId }
            );
        }

        await Promise.all([
            db.collection('reports').doc(reportId).update({
                status: 'escalated',
                escalatedAt: admin.firestore.FieldValue.serverTimestamp(),
                escalationReason: 'Auto-escalation: No verification within 30 minutes',
            }),
            event.data.ref.update({ status: 'processed', processedAt: admin.firestore.FieldValue.serverTimestamp() }),
        ]);
    }
);

// ─────────────────────────────────────────────────────────────────────────────
// 5. distributeValidatedAlert — Firestore onUpdate Trigger
//    Fires when reports/{reportId} status changes to 'validated'
// ─────────────────────────────────────────────────────────────────────────────

exports.distributeValidatedAlert = onDocumentUpdated(
    { document: 'reports/{reportId}', region: 'us-central1' },
    async (event) => {
        const before = event.data.before.data();
        const after = event.data.after.data();
        if (before.status === 'validated' || after.status !== 'validated') return;

        const { reportId } = event.params;
        const lga = after.lga || '';
        const hazardType = after.hazardType || 'Hazard';
        const severity = after.severity || 'HIGH';
        const ward = after.ward || '';
        const safeLga = lga.toLowerCase().replace(/[^a-z0-9]/g, '_');

        try {
            await messaging.send({
                topic: `lga_${safeLga}`,
                notification: {
                    title: `🚨 ${severity} Alert: ${hazardType}`,
                    body: `Verified hazard in ${ward}, ${lga}. Tap to view.`,
                },
                data: { type: 'validated_alert', reportId, hazardType, severity, lga, ward },
                android: { priority: 'high', notification: { channelId: 'alerts_channel', priority: 'max' } },
            });
            console.log(`distributeValidatedAlert: FCM sent to lga_${safeLga}`);
        } catch (err) {
            console.error(`distributeValidatedAlert topic send failed: ${err.message}`);
        }
    }
);
