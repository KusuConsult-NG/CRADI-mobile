const { Resend } = require('resend');
const templates = require('./email_templates');

/**
 * Send Email Cloud Function
 * 
 * Sends emails via Resend API for CRADI Mobile
 * 
 * Environment Variables Required:
 * - RESEND_API_KEY: Resend API key
 * - FROM_EMAIL: Sender email address (default: noreply@cradi.ng)
 * - FROM_NAME: Sender display name (default: CRADI Mobile)
 * 
 * Request Payload:
 * {
 *   "to": "recipient@example.com" | ["email1@example.com", "email2@example.com"],
 *   "template": "verification" | "alert" | "statusUpdate" | "welcome",
 *   "data": { ...template-specific data }
 * }
 */

module.exports = async ({ req, res, log, error }) => {
    try {
        // Validate environment variables
        const RESEND_API_KEY = process.env.RESEND_API_KEY;
        if (!RESEND_API_KEY) {
            error('RESEND_API_KEY environment variable is not set');
            return res.json({ success: false, error: 'Email service not configured' }, 500);
        }

        const FROM_EMAIL = process.env.FROM_EMAIL || 'noreply@cradi.ng';
        const FROM_NAME = process.env.FROM_NAME || 'CRADI Mobile';

        // Parse request payload
        let payload;
        try {
            payload = typeof req.body === 'string' ? JSON.parse(req.body) : req.body;
        } catch (e) {
            error(`Failed to parse request body: ${e.message}`);
            return res.json({ success: false, error: 'Invalid request payload' }, 400);
        }

        const { to, template, data = {} } = payload;

        // Validate required fields
        if (!to) {
            error('Missing required field: to');
            return res.json({ success: false, error: 'Recipient email address is required' }, 400);
        }

        if (!template) {
            error('Missing required field: template');
            return res.json({ success: false, error: 'Email template is required' }, 400);
        }

        // Validate template exists
        if (!templates[template]) {
            error(`Invalid template: ${template}`);
            return res.json({
                success: false,
                error: `Template '${template}' not found. Valid templates: ${Object.keys(templates).join(', ')}`
            }, 400);
        }

        // Initialize Resend client
        const resend = new Resend(RESEND_API_KEY);

        // Generate email content from template
        const { subject, html } = templates[template](data);

        log(`Sending ${template} email to: ${Array.isArray(to) ? to.join(', ') : to}`);

        // Prepare email options
        const emailOptions = {
            from: `${FROM_NAME} <${FROM_EMAIL}>`,
            to: Array.isArray(to) ? to : [to],
            subject,
            html
        };

        // Send email via Resend
        const result = await resend.emails.send(emailOptions);

        log(`Email sent successfully. ID: ${result.data?.id || 'N/A'}`);

        return res.json({
            success: true,
            messageId: result.data?.id,
            template,
            recipients: Array.isArray(to) ? to.length : 1
        });

    } catch (err) {
        error(`Send email error: ${err.message}`);
        return res.json({
            success: false,
            error: err.message
        }, 500);
    }
};
