/**
 * Email Alert Distribution Function
 * Supports:
 * 1. Resend API (default)
 * 2. SMTP / Gmail (fallback/alternative)
 */

module.exports = async ({ req, res, log, error }) => {
    // Helper for Appwrite API calls
    const appwriteCall = async (method, path, body = null, params = null) => {
        let url = `${process.env.APPWRITE_FUNCTION_ENDPOINT}${path}`;

        if (params) {
            const qs = Object.entries(params)
                .map(([k, v]) => {
                    if (Array.isArray(v)) {
                        return v.map(val => `${k}[]=${encodeURIComponent(val)}`).join('&');
                    }
                    return `${k}=${encodeURIComponent(v)}`;
                })
                .join('&');
            url += `?${qs}`;
        }

        const options = {
            method,
            headers: {
                'X-Appwrite-Project': process.env.APPWRITE_FUNCTION_PROJECT_ID,
                'X-Appwrite-Key': process.env.APPWRITE_API_KEY,
                'Content-Type': 'application/json'
            }
        };

        if (body) {
            options.body = JSON.stringify(body);
        }

        const response = await fetch(url, options);
        if (!response.ok) {
            const text = await response.text();
            throw new Error(`Appwrite API Error [${method} ${path}]: ${response.status} ${text}`);
        }
        return response.json();
    };

    /**
     * Helper: Send Email via SMTP
     */
    const sendSmtpEmail = async (to, subject, html, fromName, fromEmail) => {
        const nodemailer = require('nodemailer');

        const transporter = nodemailer.createTransport({
            host: process.env.SMTP_HOST,
            port: parseInt(process.env.SMTP_PORT || '587'),
            secure: process.env.SMTP_SECURE === 'true', // true for 465, false for other ports
            auth: {
                user: process.env.SMTP_USER,
                pass: process.env.SMTP_PASS,
            },
        });

        const info = await transporter.sendMail({
            from: `"${fromName}" <${process.env.SMTP_USER}>`, // Gmail often requires user as from
            to: Array.isArray(to) ? to.join(',') : to,
            subject: subject,
            html: html,
        });

        return info.messageId;
    };

    /**
     * Helper: Send Email via Resend
     */
    const sendResendEmail = async (to, subject, html, fromName, fromEmail) => {
        const RESEND_API_KEY = process.env.RESEND_API_KEY;
        if (!RESEND_API_KEY) throw new Error('RESEND_API_KEY not configured');

        const response = await fetch('https://api.resend.com/emails', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${RESEND_API_KEY}`
            },
            body: JSON.stringify({
                from: `${fromName} <${fromEmail}>`,
                to: Array.isArray(to) ? to : [to],
                subject: subject,
                html: html
            })
        });

        if (!response.ok) {
            const errorText = await response.text();
            throw new Error(`Resend API Error: ${response.status} ${errorText}`);
        }

        const data = await response.json();
        return data.id;
    };

    try {
        log('Starting Alert Distribution Function (Hybrid Mode)...');

        // Fallback to body if payload is empty
        const rawPayload = req.payload || req.body;

        if (!rawPayload) {
            error('Request payload is empty');
            return res.json({ success: false, error: 'Empty payload' });
        }

        const payload = typeof rawPayload === 'string' ? JSON.parse(rawPayload) : rawPayload;
        const DATABASE_ID = process.env.DATABASE_ID;
        const AUTHORITIES_COLLECTION_ID = process.env.AUTHORITIES_COLLECTION_ID || 'authorities';

        // ---------------------------------------------------------
        // MODE 1: DIRECT EMAIL
        // ---------------------------------------------------------
        if (payload.type === 'direct-email' || payload.template) {

            const FROM_EMAIL = process.env.FROM_EMAIL || 'no-reply@cradi.westgatestratagem.com';
            const FROM_NAME = process.env.FROM_NAME || 'EWER App';

            let subject = 'Notification';
            let html = '';

            if (payload.template === 'verification') {
                subject = 'Verify your EWER Account';
                html = `
                    <h1>Verify your account</h1>
                    <p>Hello ${payload.data.name},</p>
                    <p>Your verification code is:</p>
                    <h2 style="color: #007bff; letter-spacing: 5px;">${payload.data.code}</h2>
                    <p>This code will expire in 10 minutes.</p>
                 `;
            } else if (payload.template === 'welcome') {
                subject = 'Welcome to EWER';
                html = `
                    <h1>Welcome, ${payload.data.name}!</h1>
                    <p>Thank you for joining the Early Warning and Early Response system.</p>
                    <p>Your role: <strong>${payload.data.role}</strong></p>
                `;
            } else {
                subject = payload.subject || 'Notification';
                html = payload.html || payload.body || '<p>No content</p>';
            }

            // Decide Provider
            if (process.env.SMTP_HOST && process.env.SMTP_USER && process.env.SMTP_PASS) {
                log(`Sending email via SMTP to ${payload.to}`);
                const msgId = await sendSmtpEmail(payload.to, subject, html, FROM_NAME, FROM_EMAIL);
                return res.json({ success: true, messageId: msgId, method: 'smtp' });
            } else {
                log(`Sending email via Resend to ${payload.to}`);
                const msgId = await sendResendEmail(payload.to, subject, html, FROM_NAME, FROM_EMAIL);
                return res.json({ success: true, messageId: msgId, method: 'resend' });
            }
        }

        // ---------------------------------------------------------
        // MODE 2: ALERT DISTRIBUTION (Legacy Logic via Fetch)
        // ---------------------------------------------------------
        if (payload.status !== 'validated') {
            log(`Report ${payload.$id} status is '${payload.status}', not sending alerts`);
            return res.json({ success: true, message: 'Status not validated. Skipped.' });
        }

        log(`Processing validated report: ${payload.$id} (${payload.hazardType})`);

        // List all Authorities and filter in memory to bypass strict string matching
        const authResponse = await appwriteCall('GET', `/databases/${DATABASE_ID}/collections/${AUTHORITIES_COLLECTION_ID}/documents`, null, {
            'queries': [
                `limit(2000)` // Pull globally, filter precisely
            ]
        });

        const normalize = (s) => (s || '').toString().toLowerCase().replace(/[^a-z0-9]/g, '');
        const targetState = normalize(payload.state);
        const targetLga = normalize(payload.lga);

        const authorities = authResponse.documents.filter(a => {
            return normalize(a.state) === targetState && normalize(a.lga) === targetLga;
        });
        const authorityEmails = authorities.map(a => a.email).filter(Boolean);

        log(`Found ${authorities.length} authorities, ${authorityEmails.length} with emails`);

        if (authorityEmails.length === 0) {
            log('No authority emails found for this location');
            return res.json({
                success: true,
                message: 'No authority emails found',
                authoritiesFound: authorities.length
            });
        }

        // Send emails
        let emailsSent = 0;
        let emailsFailed = 0;

        const FROM_EMAIL = process.env.FROM_EMAIL || 'no-reply@cradi.westgatestratagem.com';
        const FROM_NAME = process.env.FROM_NAME || 'EWER App';
        const emailSubject = `[CRADI ALERT] ${payload.severity.toUpperCase()} ${payload.hazardType} - ${payload.lga}`;
        const emailBody = `CRADI DISASTER ALERT\nSeverity: ${payload.severity}\nHazard: ${payload.hazardType}\nLocation: ${payload.ward}, ${payload.lga}, ${payload.state}\n\n${payload.description}`;

        // Prepare provider
        const useSmtp = (process.env.SMTP_HOST && process.env.SMTP_USER && process.env.SMTP_PASS);

        for (const email of authorityEmails) {
            try {
                if (useSmtp) {
                    await sendSmtpEmail(email, emailSubject, `<pre>${emailBody}</pre>`, FROM_NAME, FROM_EMAIL);
                } else {
                    await sendResendEmail(email, emailSubject, `<pre>${emailBody}</pre>`, FROM_NAME, FROM_EMAIL);
                }
                emailsSent++;
            } catch (e) {
                emailsFailed++;
                error(e.message);
            }
        }

        log(`Alert logic complete. Emails sent: ${emailsSent}, Failed: ${emailsFailed}`);
        return res.json({ success: true, emailsSent, emailsFailed });

    } catch (err) {
        error(`Global Error: ${err.message}`);
        error(err.stack);
        return res.json({ success: false, error: err.message }, 500);
    }
};
