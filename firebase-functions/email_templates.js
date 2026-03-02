/**
 * Email Templates for CRADI Mobile
 *
 * Each export is a function (data) => { subject, html }.
 * The `data` object shape is documented per template.
 *
 * Template keys must match the `type` field sent by EmailService in the Flutter app:
 *   verification  — sendVerificationCode()
 *   welcome       — sendWelcomeEmail()
 *   hazardAlert   — sendHazardAlert()
 *   reportUpdate  — sendReportStatusUpdate()
 *   passwordReset — sendPasswordReset()
 */

'use strict';

const BRAND_RED = '#C62828';
const BRAND_DARK_RED = '#B71C1C';

function header(title, subtitle = '') {
    return `
    <div style="background: linear-gradient(135deg, ${BRAND_RED} 0%, ${BRAND_DARK_RED} 100%); padding: 30px; text-align: center;">
      <h1 style="color: white; margin: 0; font-size: 24px;">${title}</h1>
      ${subtitle ? `<p style="color: white; margin: 5px 0 0 0; opacity: 0.9;">${subtitle}</p>` : ''}
    </div>`;
}

function footer(message = 'This is an automated message from CRADI Mobile. Please do not reply.') {
    return `
    <div style="background-color: #f9f9f9; padding: 20px 30px; text-align: center; border-top: 1px solid #e0e0e0;">
      <p style="color: #999; font-size: 12px; margin: 0;">${message}</p>
    </div>`;
}

function shell(headerHtml, bodyHtml, footerHtml) {
    return `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="margin: 0; padding: 20px; font-family: Arial, sans-serif; background-color: #f5f5f5;">
  <div style="max-width: 600px; margin: 0 auto; background-color: white; border-radius: 8px; overflow: hidden;">
    ${headerHtml}
    ${bodyHtml}
    ${footerHtml}
  </div>
</body>
</html>`;
}

const templates = {
    /**
     * OTP email sent during registration and resend-code flows.
     * data: { code: string, name?: string }
     */
    verification: (data) => ({
        subject: `Your CRADI Verification Code: ${data.code}`,
        html: shell(
            header('CRADI Mobile', 'Early Warning System'),
            `<div style="padding: 40px 30px;">
              <h2 style="color: #333; margin-top: 0;">Verification Code</h2>
              <p style="color: #666; line-height: 1.6;">Hello ${data.name || 'User'},</p>
              <p style="color: #666; line-height: 1.6;">Your one-time verification code is:</p>
              <div style="background-color: #f5f5f5; border-left: 4px solid ${BRAND_RED}; padding: 20px; margin: 30px 0; text-align: center;">
                <h1 style="color: ${BRAND_RED}; font-size: 42px; margin: 0; letter-spacing: 8px; font-family: 'Courier New', monospace;">${data.code}</h1>
              </div>
              <p style="color: #999; font-size: 14px; line-height: 1.6;">
                This code expires in <strong>10 minutes</strong>. Do not share it with anyone.
              </p>
            </div>`,
            footer(),
        ),
    }),

    /**
     * Welcome email after registration.
     * data: { name: string, email: string, role?: string }
     */
    welcome: (data) => ({
        subject: 'Welcome to CRADI Mobile - Early Warning System',
        html: shell(
            header('Welcome to CRADI!', 'Climate Resilience &amp; Development Initiative'),
            `<div style="padding: 40px 30px;">
              <h2 style="color: #333; margin-top: 0;">Hello ${data.name}! 👋</h2>
              <p style="color: #666; line-height: 1.6;">
                Thank you for joining the CRADI Mobile Early Warning System. Your account has been successfully created.
              </p>
              <div style="background-color: #e3f2fd; padding: 20px; border-radius: 4px; margin: 20px 0;">
                ${data.role ? `<p style="margin: 0; color: #1976d2;"><strong>Your Role:</strong> ${data.role}</p>` : ''}
                <p style="margin: ${data.role ? '10px' : '0'} 0 0 0; color: #1976d2;"><strong>Email:</strong> ${data.email}</p>
              </div>
              <h3 style="color: #333;">What you can do:</h3>
              <ul style="color: #666; line-height: 1.8;">
                <li>Report climate hazards in your area</li>
                <li>Track the status of your reports</li>
                <li>Receive real-time alerts about validated hazards</li>
                <li>Access the knowledge base and safety resources</li>
                <li>Connect with emergency authorities</li>
              </ul>
            </div>`,
            footer('Contact your local coordinator or visit the knowledge base in the app if you need help.'),
        ),
    }),

    /**
     * Hazard alert notification to authorities.
     * data: { hazardType, severity, location, description, lga?, ward?, state?, timestamp? }
     */
    hazardAlert: (data) => {
        const sevColor =
            data.severity === 'Critical' ? '#d32f2f'
                : data.severity === 'High' ? '#ff9800'
                    : '#fbc02d';
        return {
            subject: `🚨 ${(data.severity || 'ALERT').toUpperCase()}: ${data.hazardType} – ${data.location || data.lga || 'Unknown Location'}`,
            html: shell(
                `<div style="background-color: ${BRAND_RED}; padding: 20px; text-align: center; border: 3px solid ${BRAND_RED};">
                  <h1 style="color: white; margin: 0; font-size: 28px;">⚠️ EMERGENCY ALERT</h1>
                </div>`,
                `<div style="padding: 30px;">
                  <div style="background-color: #fff3e0; border-left: 4px solid #ff9800; padding: 15px; margin-bottom: 20px;">
                    <p style="margin: 0; color: #e65100; font-weight: bold;">ACTION REQUIRED: Climate Hazard Detected</p>
                  </div>
                  <table style="width: 100%; border-collapse: collapse;">
                    <tr><td style="padding: 12px; border-bottom: 1px solid #e0e0e0; color: #666; font-weight: bold; width: 30%;">Hazard Type:</td><td style="padding: 12px; border-bottom: 1px solid #e0e0e0; color: #333;">${data.hazardType}</td></tr>
                    <tr><td style="padding: 12px; border-bottom: 1px solid #e0e0e0; color: #666; font-weight: bold;">Severity:</td>
                        <td style="padding: 12px; border-bottom: 1px solid #e0e0e0;">
                          <span style="background-color: ${sevColor}; color: white; padding: 4px 12px; border-radius: 4px; font-weight: bold;">${(data.severity || '').toUpperCase()}</span>
                        </td>
                    </tr>
                    <tr><td style="padding: 12px; border-bottom: 1px solid #e0e0e0; color: #666; font-weight: bold;">Location:</td><td style="padding: 12px; border-bottom: 1px solid #e0e0e0; color: #333;">${data.location || [data.ward, data.lga].filter(Boolean).join(', ')}</td></tr>
                    ${data.state ? `<tr><td style="padding: 12px; border-bottom: 1px solid #e0e0e0; color: #666; font-weight: bold;">State:</td><td style="padding: 12px; border-bottom: 1px solid #e0e0e0; color: #333;">${data.state}</td></tr>` : ''}
                    ${data.timestamp ? `<tr><td style="padding: 12px; border-bottom: 1px solid #e0e0e0; color: #666; font-weight: bold;">Reported:</td><td style="padding: 12px; border-bottom: 1px solid #e0e0e0; color: #333;">${data.timestamp}</td></tr>` : ''}
                  </table>
                  <div style="margin-top: 20px; padding: 20px; background-color: #f5f5f5; border-radius: 4px;">
                    <h3 style="margin-top: 0; color: #333;">Description:</h3>
                    <p style="color: #666; line-height: 1.6; margin: 0;">${data.description}</p>
                  </div>
                </div>`,
                footer('CRADI Mobile – Climate Resilience and Development Initiative'),
            ),
        };
    },

    /**
     * Report status update notification.
     * data: { reportId, status, message, reporterName? }
     */
    reportUpdate: (data) => {
        const statusColor =
            data.status === 'Validated' ? '#4caf50'
                : data.status === 'Resolved' ? '#2196f3'
                    : '#ff9800';
        return {
            subject: `Report Update: ${data.status} – Report #${data.reportId}`,
            html: shell(
                header('Report Status Update'),
                `<div style="padding: 30px;">
                  <p style="color: #666; line-height: 1.6;">Hello ${data.reporterName || 'User'},</p>
                  <p style="color: #666; line-height: 1.6;">Your hazard report has been updated:</p>
                  <table style="width: 100%; border-collapse: collapse; margin: 20px 0;">
                    <tr><td style="padding: 12px; border-bottom: 1px solid #e0e0e0; color: #666; font-weight: bold;">Report ID:</td><td style="padding: 12px; border-bottom: 1px solid #e0e0e0; color: #333; font-family: monospace;">${data.reportId}</td></tr>
                    <tr><td style="padding: 12px; border-bottom: 1px solid #e0e0e0; color: #666; font-weight: bold;">New Status:</td>
                        <td style="padding: 12px; border-bottom: 1px solid #e0e0e0;">
                          <span style="background-color: ${statusColor}; color: white; padding: 4px 12px; border-radius: 4px; font-weight: bold;">${(data.status || '').toUpperCase()}</span>
                        </td>
                    </tr>
                  </table>
                  ${data.message ? `<div style="padding: 20px; background-color: #f5f5f5; border-radius: 4px;"><h3 style="margin-top: 0; color: #333;">Message from Coordinator:</h3><p style="color: #666; line-height: 1.6; margin: 0;">${data.message}</p></div>` : ''}
                  <p style="color: #666; line-height: 1.6; margin-top: 20px;">
                    Thank you for helping keep our communities safe through the CRADI Early Warning System.
                  </p>
                </div>`,
                footer('CRADI Mobile – Early Warning System'),
            ),
        };
    },

    /**
     * Password reset link email.
     * data: { resetLink: string }
     */
    passwordReset: (data) => ({
        subject: 'Reset Your CRADI Password',
        html: shell(
            header('Password Reset', 'CRADI Mobile'),
            `<div style="padding: 40px 30px;">
              <h2 style="color: #333; margin-top: 0;">Reset Your Password</h2>
              <p style="color: #666; line-height: 1.6;">
                We received a request to reset the password for your CRADI account. Click the button below to set a new password:
              </p>
              <div style="text-align: center; margin: 30px 0;">
                <a href="${data.resetLink}" style="background-color: ${BRAND_RED}; color: white; padding: 14px 32px; text-decoration: none; border-radius: 6px; font-weight: bold; font-size: 16px; display: inline-block;">
                  Reset Password
                </a>
              </div>
              <p style="color: #999; font-size: 14px; line-height: 1.6;">
                This link expires in <strong>1 hour</strong>. If you did not request a password reset, please ignore this email — your account is safe.
              </p>
            </div>`,
            footer(),
        ),
    }),
};

module.exports = templates;
