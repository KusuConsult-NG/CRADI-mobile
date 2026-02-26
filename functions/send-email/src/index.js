#!/usr/bin/env node
/**
 * Firebase HTTPS Callable Cloud Function: sendTransactionalEmail
 * 
 * Called from Flutter via:
 *   http.post('https://us-central1-ewer-8f788.cloudfunctions.net/sendTransactionalEmail', ...)
 *   with Authorization: Bearer <Firebase ID token>
 *
 * Environment variables (set via Firebase Functions config or .env):
 *   RESEND_API_KEY   — Resend API key
 *   FROM_EMAIL       — Sender email (default: noreply@cradi.ng)
 *   FROM_NAME        — Sender display name (default: EWER Alert System)
 *
 * Request body:
 *   { "type": "welcome"|"verification"|"alert"|"statusUpdate",
 *     "to": "user@example.com",
 *     "data": { ...template-specific fields } }
 *
 * Response:
 *   { "success": true, "messageId": "resend-id" }
 */

const { onRequest } = require('firebase-functions/v2/https');
const { getAuth } = require('firebase-admin/auth');
const { initializeApp, getApps } = require('firebase-admin/app');
const { Resend } = require('resend');
const templates = require('./email_templates');

if (!getApps().length) initializeApp();

// Email rate limit: 1 per recipient per minute (simple in-memory guard)
const recentSends = new Map();
function isRateLimited(email) {
    const last = recentSends.get(email);
    if (last && Date.now() - last < 60_000) return true;
    recentSends.set(email, Date.now());
    return false;
}

exports.sendTransactionalEmail = onRequest(
    { region: 'us-central1', invoker: 'private' },
    async (req, res) => {
        // Only accept POST
        if (req.method !== 'POST') {
            return res.status(405).json({ success: false, error: 'Method not allowed' });
        }

        // ── Auth verification ──────────────────────────────────────────────────
        const authHeader = req.headers['authorization'] || '';
        if (!authHeader.startsWith('Bearer ')) {
            return res.status(401).json({ success: false, error: 'Unauthorized' });
        }
        const idToken = authHeader.slice(7);
        try {
            await getAuth().verifyIdToken(idToken);
        } catch (_) {
            return res.status(401).json({ success: false, error: 'Invalid token' });
        }

        // ── Validate env ───────────────────────────────────────────────────────
        const RESEND_API_KEY = process.env.RESEND_API_KEY;
        if (!RESEND_API_KEY) {
            console.error('RESEND_API_KEY not configured');
            return res.status(500).json({ success: false, error: 'Email service not configured' });
        }

        const FROM_EMAIL = process.env.FROM_EMAIL || 'noreply@cradi.ng';
        const FROM_NAME = process.env.FROM_NAME || 'EWER Alert System';

        // ── Parse body ─────────────────────────────────────────────────────────
        const { type, to, data = {} } = req.body;

        if (!to || typeof to !== 'string') {
            return res.status(400).json({ success: false, error: 'to is required' });
        }
        if (!type || typeof type !== 'string') {
            return res.status(400).json({ success: false, error: 'type is required' });
        }
        if (!templates[type]) {
            return res.status(400).json({
                success: false,
                error: `Unknown type '${type}'. Valid: ${Object.keys(templates).join(', ')}`,
            });
        }

        // ── Rate limit ─────────────────────────────────────────────────────────
        if (isRateLimited(to)) {
            return res.status(429).json({ success: false, error: 'Rate limit: wait 60s' });
        }

        // ── Send via Resend ────────────────────────────────────────────────────
        try {
            const { subject, html } = templates[type](data);
            const resend = new Resend(RESEND_API_KEY);
            const result = await resend.emails.send({
                from: `${FROM_NAME} <${FROM_EMAIL}>`,
                to: [to],
                subject,
                html,
            });

            console.log(`[sendTransactionalEmail] type=${type} to=${to} id=${result.data?.id}`);
            return res.status(200).json({ success: true, messageId: result.data?.id });
        } catch (err) {
            console.error(`[sendTransactionalEmail] error:`, err.message);
            return res.status(500).json({ success: false, error: err.message });
        }
    },
);
