// Pure functions: who gets notified and what the notification says.
import { sanitizeTag } from './tags.js';

export const VERIFIER_ROLES = ['ewm'];
export const ESCALATION_LGA_ROLES = ['ldp_coordinator', 'ewr'];
export const ESCALATION_GLOBAL_ROLES = ['project_staff', 'ewv'];
export const RECIPIENT_LIMIT = 50;
// Worded without a duration: the timeout is app_settings.escalation_timeout_minutes.
export const ESCALATION_REASON = 'Auto-escalation: Not verified within the escalation timeout';
export const DISPUTE_REASON = 'Disputed by a peer monitor';

/**
 * escalation_reason written by the dispute handler for outbox event `eventId`,
 * so a retry can tell its own escalation apart from one made by another
 * (earlier) dispute event and not notify twice.
 */
export function disputeReasonFor(eventId) {
  return `${DISPUTE_REASON} [event ${eventId}]`;
}

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

// Push privacy: OneSignal external_id / tag targeting can be claimed by another
// device unless Identity Verification is enabled (see README), so pushes carry
// no location names, hazard free text, descriptions or rejection reasons —
// only generic text plus ids/type for the app to load details after sign-in.

export const ADMIN_ALERT_TITLE_MAX = 80;
export const ADMIN_ALERT_BODY_MAX = 240;

/** Collapses whitespace / control characters and caps the length (with an ellipsis). */
export function clampText(value, max) {
  const text = String(value ?? '')
    .replace(/[\u0000-\u001f\u007f]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  if (text.length <= max) return text;
  return `${text.slice(0, Math.max(0, max - 1)).trimEnd()}…`;
}

const REPORT_STATUSES = new Set(['pending', 'verified', 'approved', 'rejected']);
const ALERT_SEVERITIES = new Set(['info', 'warning', 'critical']);

export function verificationRequestNotification(report) {
  return {
    title: '📋 Verification Request',
    body: 'A report in your area needs verification. Open the app for details.',
    data: { type: 'verification_request', report_id: report.id },
  };
}

// The rejection reason is deliberately not included; the app shows it after sign-in.
export function reporterStatusMessage(status) {
  switch (status) {
    case 'verified':
      return '✅ Your report has been verified by peers and is awaiting final approval.';
    case 'approved':
      return '✅ Your report has been approved and an alert has been issued.';
    case 'rejected':
      return '❌ Your report was rejected — open the app for details.';
    case 'pending':
      return '⏳ Your report is awaiting peer verification.';
    default:
      return 'Your report status has changed — open the app for details.';
  }
}

export function reporterStatusNotification(report, status) {
  const data = { type: 'report_status', report_id: report.id };
  if (REPORT_STATUSES.has(status)) data.status = status;
  return {
    title: '📬 Report Update',
    body: reporterStatusMessage(status),
    data,
  };
}

export function shouldBroadcastApproval(oldStatus, newStatus) {
  return newStatus === 'approved' && oldStatus !== 'approved';
}

export function validatedAlertNotification(report) {
  return {
    title: '🚨 Verified Hazard Alert',
    body: 'A hazard in your area has been verified. Open the app for details.',
    data: { type: 'validated_alert', report_id: report.id },
  };
}

/**
 * Where an admin alert goes: { all: true } or { all: false, tags } where `tags`
 * is an object of (already sanitised) OneSignal tag values that must ALL match.
 *
 *   target_state NULL, target_lga 'All'  -> everyone
 *   target_state S,    target_lga 'All'  -> { state: S }          (every LGA of S)
 *   target_state S,    target_lga X      -> { lga: X, state: S }  (X in S only; Obi exists in two states)
 *
 * Since migration 20260927080000 those are the only three shapes the database
 * stores: an LGA without a state is rejected by the check constraint
 * alerts_target_lga_needs_state, because an LGA name alone can mean two
 * different places. The fourth branch below —
 *
 *   target_state NULL, target_lga X      -> { lga: X }            (X in any state)
 *
 * is therefore unreachable from `alerts`, and is kept only so a hand-built row
 * or a stale replica degrades to the old name-only match instead of throwing.
 *
 * Devices without a `state` tag (app versions that predate it, or profiles
 * without a state) never match a state-scoped alert.
 */
export function alertTarget(alert) {
  const lga = String(alert?.target_lga ?? '').trim();
  const state = String(alert?.target_state ?? '').trim();
  const allLgas = !lga || lga.toLowerCase() === 'all';
  if (!state) return allLgas ? { all: true } : { all: false, tags: { lga: sanitizeTag(lga) } };
  const tags = allLgas ? {} : { lga: sanitizeTag(lga) };
  tags.state = sanitizeTag(state);
  return { all: false, tags };
}

// Admin alerts are intentionally public broadcasts, so their text is sent,
// but normalised and length-capped.
export function adminAlertNotification(alert) {
  const title = clampText(alert.title, ADMIN_ALERT_TITLE_MAX) || 'Alert';
  const body = clampText(alert.message, ADMIN_ALERT_BODY_MAX) || title;
  return {
    title,
    body,
    data: {
      type: 'admin_alert',
      alert_id: alert.id,
      severity: ALERT_SEVERITIES.has(alert.severity) ? alert.severity : null,
    },
  };
}

export function escalationNotification(report) {
  return {
    title: '⏰ Unverified Report Escalated',
    body: 'A report has not been verified in time and needs review. Open the app for details.',
    data: { type: 'escalation_auto', report_id: report.id },
  };
}

export function disputeEscalationNotification(report) {
  return {
    title: '⚠️ Disputed Report Escalated',
    body: 'A report was disputed by a peer monitor and needs review. Open the app for details.',
    data: { type: 'escalation', report_id: report.id },
  };
}
