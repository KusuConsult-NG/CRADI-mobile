// Transactional email templates (ported from firebase-functions/email_templates.js).
// Each template is (data) => { subject, html }. All caller-supplied values are
// HTML-escaped. 'verification' and 'passwordReset' were dropped: Supabase Auth
// sends confirmation and password-recovery emails itself.

const BRAND_RED = '#C62828';
const BRAND_DARK_RED = '#B71C1C';

export function escapeHtml(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

// Subjects are plain text; just strip control characters / newlines.
function plain(value, max = 150) {
  return String(value ?? '').replace(/[\u0000-\u001f\u007f]/g, ' ').slice(0, max);
}

const e = escapeHtml;

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

const row = (label, valueHtml) =>
  `<tr><td style="padding: 12px; border-bottom: 1px solid #e0e0e0; color: #666; font-weight: bold; width: 30%;">${label}</td><td style="padding: 12px; border-bottom: 1px solid #e0e0e0; color: #333;">${valueHtml}</td></tr>`;

export const templates = {
  /** data: { name, email, role? } */
  welcome: (data) => ({
    subject: 'Welcome to CRADI Mobile - Early Warning System',
    html: shell(
      header('Welcome to CRADI!', 'Climate Resilience &amp; Development Initiative'),
      `<div style="padding: 40px 30px;">
        <h2 style="color: #333; margin-top: 0;">Hello ${e(data.name || 'User')}! 👋</h2>
        <p style="color: #666; line-height: 1.6;">
          Thank you for joining the CRADI Mobile Early Warning System. Your account has been successfully created.
        </p>
        <div style="background-color: #e3f2fd; padding: 20px; border-radius: 4px; margin: 20px 0;">
          ${data.role ? `<p style="margin: 0; color: #1976d2;"><strong>Your Role:</strong> ${e(data.role)}</p>` : ''}
          ${data.email ? `<p style="margin: ${data.role ? '10px' : '0'} 0 0 0; color: #1976d2;"><strong>Email:</strong> ${e(data.email)}</p>` : ''}
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

  /** data: { hazardType, severity, location, description, lga?, ward?, state?, timestamp? } */
  hazardAlert: (data) => {
    const sev = String(data.severity || '').toLowerCase();
    const sevColor = sev === 'critical' ? '#d32f2f' : sev === 'high' ? '#ff9800' : '#fbc02d';
    const location = data.location || [data.ward, data.lga].filter(Boolean).join(', ');
    return {
      subject: plain(
        `🚨 ${String(data.severity || 'ALERT').toUpperCase()}: ${data.hazardType || 'Hazard'} – ${data.location || data.lga || 'Unknown Location'}`,
      ),
      html: shell(
        `<div style="background-color: ${BRAND_RED}; padding: 20px; text-align: center; border: 3px solid ${BRAND_RED};">
          <h1 style="color: white; margin: 0; font-size: 28px;">⚠️ EMERGENCY ALERT</h1>
        </div>`,
        `<div style="padding: 30px;">
          <div style="background-color: #fff3e0; border-left: 4px solid #ff9800; padding: 15px; margin-bottom: 20px;">
            <p style="margin: 0; color: #e65100; font-weight: bold;">ACTION REQUIRED: Climate Hazard Detected</p>
          </div>
          <table style="width: 100%; border-collapse: collapse;">
            ${row('Hazard Type:', e(data.hazardType))}
            ${row('Severity:', `<span style="background-color: ${sevColor}; color: white; padding: 4px 12px; border-radius: 4px; font-weight: bold;">${e(String(data.severity || '').toUpperCase())}</span>`)}
            ${row('Location:', e(location))}
            ${data.state ? row('State:', e(data.state)) : ''}
            ${data.timestamp ? row('Reported:', e(data.timestamp)) : ''}
          </table>
          <div style="margin-top: 20px; padding: 20px; background-color: #f5f5f5; border-radius: 4px;">
            <h3 style="margin-top: 0; color: #333;">Description:</h3>
            <p style="color: #666; line-height: 1.6; margin: 0;">${e(data.description)}</p>
          </div>
        </div>`,
        footer('CRADI Mobile – Climate Resilience and Development Initiative'),
      ),
    };
  },

  /** data: { reportId, status, message?, reporterName? } */
  reportUpdate: (data) => {
    const st = String(data.status || '').toLowerCase();
    const statusColor =
      st === 'validated' || st === 'approved' || st === 'verified' ? '#4caf50' : st === 'resolved' ? '#2196f3' : '#ff9800';
    return {
      subject: plain(`Report Update: ${data.status} – Report #${data.reportId}`),
      html: shell(
        header('Report Status Update'),
        `<div style="padding: 30px;">
          <p style="color: #666; line-height: 1.6;">Hello ${e(data.reporterName || 'User')},</p>
          <p style="color: #666; line-height: 1.6;">Your hazard report has been updated:</p>
          <table style="width: 100%; border-collapse: collapse; margin: 20px 0;">
            ${row('Report ID:', `<span style="font-family: monospace;">${e(data.reportId)}</span>`)}
            ${row('New Status:', `<span style="background-color: ${statusColor}; color: white; padding: 4px 12px; border-radius: 4px; font-weight: bold;">${e(String(data.status || '').toUpperCase())}</span>`)}
          </table>
          ${data.message ? `<div style="padding: 20px; background-color: #f5f5f5; border-radius: 4px;"><h3 style="margin-top: 0; color: #333;">Message from Coordinator:</h3><p style="color: #666; line-height: 1.6; margin: 0;">${e(data.message)}</p></div>` : ''}
          <p style="color: #666; line-height: 1.6; margin-top: 20px;">
            Thank you for helping keep our communities safe through the CRADI Early Warning System.
          </p>
        </div>`,
        footer('CRADI Mobile – Early Warning System'),
      ),
    };
  },
};

/** Returns an error string when `data` is unusable for `type`, else null. */
export function validateTemplateData(type, data) {
  if (type === 'reportUpdate' && (!data?.reportId || !data?.status)) return 'reportId and status are required';
  if (type === 'hazardAlert' && !data?.hazardType) return 'hazardType is required';
  return null;
}
