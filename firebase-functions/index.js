/**
 * Firebase HTTPS Cloud Function: sendTransactionalEmail
 *
 * Called from Flutter's EmailService via:
 *   POST https://us-central1-ewer-8f788.cloudfunctions.net/sendTransactionalEmail
 *   Authorization: Bearer <Firebase ID token>
 *
 * ⚠️  Project is on Spark plan, so Firebase Secret Manager is unavailable.
 *     Store RESEND_API_KEY in firebase-functions/.env (never commit this file!).
 *
 * Env vars (firebase-functions/.env, never committed):
 *   RESEND_API_KEY  — Resend API key  ← REQUIRED
 *   FROM_EMAIL      — Sender address  (default: noreply@cradi.ng)
 *   FROM_NAME       — Sender name     (default: EWER Alert System)
 *
 * Request body JSON:
 *   { "type": "verification"|"welcome"|"hazardAlert"|"reportUpdate"|"passwordReset",
 *     "to":   "user@example.com",
 *     "data": { ...template-specific fields } }
 *
 * Success response:
 *   { "success": true, "messageId": "<resend-id>" }
 *
 * Error response:
 *   { "success": false, "error": "<reason>" }
 */

'use strict';

const { onRequest } = require('firebase-functions/v2/https');
const { getAuth } = require('firebase-admin/auth');
const { initializeApp, getApps } = require('firebase-admin/app');
const { Resend } = require('resend');
const templates = require('./email_templates');

if (!getApps().length) initializeApp();

// Simple in-memory rate limit: 1 email per recipient per 60 s
const recentSends = new Map();
function isRateLimited(email) {
    const last = recentSends.get(email);
    if (last && Date.now() - last < 60_000) return true;
    recentSends.set(email, Date.now());
    return false;
}

exports.sendTransactionalEmail = onRequest(
    {
        region: 'us-central1',
        invoker: 'public',
    },
    async (req, res) => {
        // ── CORS preflight ───────────────────────────────────────────────────
        res.set('Access-Control-Allow-Origin', '*');
        if (req.method === 'OPTIONS') {
            res.set('Access-Control-Allow-Methods', 'POST');
            res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
            res.set('Access-Control-Max-Age', '3600');
            return res.status(204).send('');
        }

        // ── Only POST ────────────────────────────────────────────────────────
        if (req.method !== 'POST') {
            return res.status(405).json({ success: false, error: 'Method not allowed' });
        }

        // ── Firebase ID token verification ───────────────────────────────────
        // During registration an OTP is sent BEFORE the user is logged in, so
        // the token may be absent. We still require it for all other email types.
        const authHeader = req.headers['authorization'] || '';
        const isRegistrationOtp =
            req.body?.type === 'verification' &&
            !authHeader.startsWith('Bearer ');

        if (!isRegistrationOtp) {
            if (!authHeader.startsWith('Bearer ')) {
                return res.status(401).json({ success: false, error: 'Unauthorized' });
            }
            const idToken = authHeader.slice(7);
            try {
                await getAuth().verifyIdToken(idToken);
            } catch (_) {
                return res.status(401).json({ success: false, error: 'Invalid token' });
            }
        }

        // ── Validate env ─────────────────────────────────────────────────────
        const RESEND_API_KEY = process.env.RESEND_API_KEY;
        if (!RESEND_API_KEY) {
            console.error('[sendTransactionalEmail] RESEND_API_KEY not configured');
            return res.status(500).json({ success: false, error: 'Email service not configured' });
        }

        const FROM_EMAIL = process.env.FROM_EMAIL || 'noreply@cradi.ng';
        const FROM_NAME = process.env.FROM_NAME || 'EWER Alert System';

        // ── Parse + validate body ────────────────────────────────────────────
        const { type, to, data = {} } = req.body ?? {};

        if (!to || typeof to !== 'string') {
            return res.status(400).json({ success: false, error: '"to" is required' });
        }
        if (!type || typeof type !== 'string') {
            return res.status(400).json({ success: false, error: '"type" is required' });
        }
        if (!templates[type]) {
            return res.status(400).json({
                success: false,
                error: `Unknown type '${type}'. Valid: ${Object.keys(templates).join(', ')}`,
            });
        }

        // ── Rate limit ───────────────────────────────────────────────────────
        if (isRateLimited(to)) {
            return res.status(429).json({ success: false, error: 'Rate limit: wait 60 s before resending' });
        }

        // ── Send via Resend ──────────────────────────────────────────────────
        try {
            const { subject, html } = templates[type](data);
            const resend = new Resend(RESEND_API_KEY);

            const result = await resend.emails.send({
                from: `${FROM_NAME} <${FROM_EMAIL}>`,
                to: [to],
                subject,
                html,
            });

            if (result.error) {
                console.error(`[sendTransactionalEmail] Resend error:`, result.error);
                return res.status(500).json({ success: false, error: result.error.message });
            }

            console.log(`[sendTransactionalEmail] ✅ type=${type} to=${to} id=${result.data?.id}`);
            return res.status(200).json({ success: true, messageId: result.data?.id });
        } catch (err) {
            console.error(`[sendTransactionalEmail] exception:`, err.message);
            return res.status(500).json({ success: false, error: err.message });
        }
    },
);

// ─────────────────────────────────────────────────────────────────────────────
// FCM Peer Notification Functions (defined in notifications.js)
// ─────────────────────────────────────────────────────────────────────────────
const notifications = require('./notifications');
exports.sendVerificationRequest = notifications.sendVerificationRequest;
exports.sendEscalationNotification = notifications.sendEscalationNotification;
exports.sendReporterStatusUpdate = notifications.sendReporterStatusUpdate;
exports.processEscalations = notifications.processEscalations;
exports.distributeValidatedAlert = notifications.distributeValidatedAlert;

// ─────────────────────────────────────────────────────────────────────────────
// Anti-Abuse Bypass: Mint Custom Token
// ─────────────────────────────────────────────────────────────────────────────
exports.mintCustomToken = onRequest(
    {
        region: 'us-central1',
        invoker: 'public',
    },
    async (req, res) => {
        // CORS preflight
        res.set('Access-Control-Allow-Origin', '*');
        if (req.method === 'OPTIONS') {
            res.set('Access-Control-Allow-Methods', 'POST');
            res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
            res.set('Access-Control-Max-Age', '3600');
            return res.status(204).send('');
        }

        if (req.method !== 'POST') {
            return res.status(405).json({ success: false, error: 'Method not allowed' });
        }

        try {
            const authHeader = req.headers['authorization'] || '';
            if (!authHeader.startsWith('Bearer ')) {
                return res.status(401).json({ success: false, error: 'Unauthorized header missing' });
            }
            const idToken = authHeader.slice(7);

            // Verify the ID token (proves the user successfully authenticated via REST API)
            const decodedToken = await getAuth().verifyIdToken(idToken);
            const uid = decodedToken.uid;

            // Mint a custom token for native SDK sign in (bypasses Android Play Integrity checks)
            const customToken = await getAuth().createCustomToken(uid);

            return res.status(200).json({ success: true, customToken });
        } catch (err) {
            console.error('[mintCustomToken] error:', err);
            return res.status(500).json({ success: false, error: err.message });
        }
    }
);
