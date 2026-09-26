// Pure functions: who gets notified and what the notification says.
import { sanitizeTag } from './tags.js';

export const VERIFIER_ROLES = ['ewm'];
export const ESCALATION_LGA_ROLES = ['ldp_coordinator', 'ewr'];
export const ESCALATION_GLOBAL_ROLES = ['project_staff', 'ewv'];
export const RECIPIENT_LIMIT = 50;
// Worded without a duration: the timeout is app_settings.escalation_timeout_minutes.
export const ESCALATION_REASON = 'Auto-escalation: Not verified within the escalation timeout';
export const DISPUTE_REASON = 'Disputed by a peer monitor';

/** Profile filter for peer verifiers of a report (same ward AND lga, not the reporter). */
export function verifierQuery(report) {
  if (!report?.lga || !report?.ward) return null;
  return {
    roles: VERIFIER_ROLES,
    lga: report.lga,
    ward: report.ward,
    excludeId: report.user_id ?? null,
    limit: RECIPIENT_LIMIT,
  };
}

/** Profile filters for an auto-escalation: LGA coordinators/EWRs + project staff/EWVs anywhere. */
export function escalationQueries(report) {
  const queries = [
    { roles: ESCALATION_GLOBAL_ROLES, excludeId: report?.user_id ?? null, limit: RECIPIENT_LIMIT },
  ];
  if (report?.lga) {
    queries.unshift({
      roles: ESCALATION_LGA_ROLES,
      lga: report.lga,
      excludeId: report.user_id ?? null,
      limit: RECIPIENT_LIMIT,
    });
  }
  return queries;
}

/** Keeps only eligible profiles and returns their ids, deduplicated, in order. */
export function selectRecipientIds(profileLists, { excludeId = null } = {}) {
  const seen = new Set();
  const out = [];
  for (const list of profileLists) {
    for (const p of list ?? []) {
      if (!p?.id || p.id === excludeId || seen.has(p.id)) continue;
      if (p.is_approved === false || p.is_disabled === true) continue;
      seen.add(p.id);
      out.push(p.id);
    }
  }
  return out;
}

export function verificationRequestNotification(report) {
  return {
    title: '📋 Verification Request',
    body: `A hazard report in ${report.ward}, ${report.lga} needs your verification.`,
    data: { type: 'verification_request', report_id: report.id, ward: report.ward, lga: report.lga },
  };
}

export function reporterStatusMessage(status, reason) {
  switch (status) {
    case 'verified':
      return '✅ Your report has been verified by peers and is awaiting final approval.';
    case 'approved':
      return '✅ Your report has been approved and an alert has been issued.';
    case 'rejected':
      return `❌ Your report was not validated.${reason ? ` Reason: ${reason}` : ''}`;
    case 'pending':
      return '⏳ Your report is awaiting peer verification.';
    default:
      return `Your report status is now: ${status}`;
  }
}

export function reporterStatusNotification(report, status, reason) {
  return {
    title: '📬 Report Update',
    body: reporterStatusMessage(status, reason),
    data: { type: 'report_status', report_id: report.id, status },
  };
}

export function shouldBroadcastApproval(oldStatus, newStatus) {
  return newStatus === 'approved' && oldStatus !== 'approved';
}

export function validatedAlertNotification(report) {
  const severity = String(report.severity || 'high').toUpperCase();
  const hazardType = report.hazard_type || 'Hazard';
  const where = [report.ward, report.lga].filter(Boolean).join(', ');
  return {
    title: `🚨 ${severity} Alert: ${hazardType}`,
    body: `Verified hazard${where ? ` in ${where}` : ''}. Tap to view.`,
    data: {
      type: 'validated_alert',
      report_id: report.id,
      hazard_type: hazardType,
      severity: report.severity ?? null,
      lga: report.lga ?? null,
      ward: report.ward ?? null,
    },
  };
}

/** Where an admin alert goes: { all: true } or { tagKey: 'lga', tagValue }. */
export function alertTarget(alert) {
  const lga = String(alert?.target_lga ?? '').trim();
  if (!lga || lga.toLowerCase() === 'all') return { all: true };
  return { all: false, tagKey: 'lga', tagValue: sanitizeTag(lga) };
}

export function adminAlertNotification(alert) {
  return {
    title: alert.title,
    body: alert.message || alert.title,
    data: { type: 'admin_alert', alert_id: alert.id, severity: alert.severity ?? null },
  };
}

export function escalationNotification(report) {
  const hazardType = report.hazard_type || 'hazard';
  return {
    title: '⏰ Unverified Report Escalated',
    body: `A ${hazardType} report${report.lga ? ` in ${report.lga}` : ''} has not been verified in time.`,
    data: { type: 'escalation_auto', report_id: report.id, lga: report.lga ?? null },
  };
}

export function disputeEscalationNotification(report) {
  const hazardType = report.hazard_type || 'hazard';
  return {
    title: '⚠️ Disputed Report Escalated',
    body: `A ${hazardType} report${report.lga ? ` in ${report.lga}` : ''} was disputed by a peer monitor and needs review.`,
    data: { type: 'escalation', report_id: report.id, lga: report.lga ?? null },
  };
}
