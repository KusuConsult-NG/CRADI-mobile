/**
 * Who gets notified, and what the notification says.
 *
 * Ported from `backend/src/notifications.js`, which was already pure and
 * already backend-neutral — the only change is field names, because
 * Appwrite collections carry the app's camelCase rather than Postgres's
 * snake_case. Keeping the wording identical matters: these strings have
 * been read by field agents for a year, and a migration is a bad moment
 * to also reword every alert.
 */

export const VERIFIER_ROLES = ['ewm'];
export const ESCALATION_LGA_ROLES = ['ldp_coordinator', 'ewr'];
export const ESCALATION_GLOBAL_ROLES = ['project_staff', 'ewv'];
export const RECIPIENT_LIMIT = 50;

// Worded without a duration: the timeout is app_settings.escalation_timeout_minutes.
export const ESCALATION_REASON =
  'Auto-escalation: Not verified within the escalation timeout';
export const DISPUTE_REASON = 'Disputed by a peer monitor';

/**
 * The `escalationReason` the dispute handler writes for outbox event
 * [eventId], so a retry can tell its own escalation from one made by an
 * earlier dispute event and not notify twice.
 */
export const disputeReasonFor = (eventId) => `${DISPUTE_REASON} [event ${eventId}]`;

/** Peer verifiers of a report: same ward AND lga, never the reporter. */
export function verifierQuery(report) {
  if (!report?.lga || !report?.ward) return null;
  return {
    roles: VERIFIER_ROLES,
    lga: report.lga,
    ward: report.ward,
    excludeId: report.userId ?? null,
    limit: RECIPIENT_LIMIT,
  };
}

/** An escalation: LGA coordinators/EWRs, plus project staff/EWVs anywhere. */
export function escalationQueries(report) {
  const queries = [
    {
      roles: ESCALATION_GLOBAL_ROLES,
      excludeId: report?.userId ?? null,
      limit: RECIPIENT_LIMIT,
    },
  ];
  if (report?.lga) {
    queries.unshift({
      roles: ESCALATION_LGA_ROLES,
      lga: report.lga,
      excludeId: report.userId ?? null,
      limit: RECIPIENT_LIMIT,
    });
  }
  return queries;
}

/** Eligible profiles only, deduplicated, in order. */
export function selectRecipientIds(profileLists, { excludeId = null } = {}) {
  const seen = new Set();
  const out = [];
  for (const list of profileLists) {
    for (const p of list ?? []) {
      const id = p?.$id ?? p?.id;
      if (!id || id === excludeId || seen.has(id)) continue;
      if (p.isApproved === false || p.isDisabled === true) continue;
      seen.add(id);
      out.push(id);
    }
  }
  return out;
}

// Push privacy, unchanged from the Railway worker: a push carries no
// location names, hazard free text, descriptions or rejection reasons —
// only generic wording plus ids for the app to load details after
// sign-in. The reasoning was OneSignal-specific (external_id targeting
// can be claimed by another device without Identity Verification) and it
// survives the move: an Appwrite push target is a device token the user
// can also lose control of, and a lock screen is a lock screen.

export const ADMIN_ALERT_TITLE_MAX = 80;
export const ADMIN_ALERT_BODY_MAX = 240;

/** Collapses whitespace and control characters, and caps the length. */
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

export const verificationRequestNotification = (report) => ({
  title: '📋 Verification Request',
  body: 'A report in your area needs verification. Open the app for details.',
  data: { type: 'verification_request', report_id: report.$id },
});

/** The rejection reason is deliberately absent; the app shows it after sign-in. */
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
  const data = { type: 'report_status', report_id: report.$id };
  if (REPORT_STATUSES.has(status)) data.status = status;
  return { title: '📬 Report Update', body: reporterStatusMessage(status), data };
}

export const shouldBroadcastApproval = (oldStatus, newStatus) =>
  newStatus === 'approved' && oldStatus !== 'approved';

export const validatedAlertNotification = (report) => ({
  title: '🚨 Verified Hazard Alert',
  body: 'A hazard in your area has been verified. Open the app for details.',
  data: { type: 'validated_alert', report_id: report.$id },
});

export const escalationNotification = (report) => ({
  title: '⏰ Unverified Report Escalated',
  body: 'A report has not been verified in time and needs review. Open the app for details.',
  data: { type: 'escalation_auto', report_id: report.$id },
});

export const disputeEscalationNotification = (report) => ({
  title: '⚠️ Disputed Report Escalated',
  body: 'A report was disputed by a peer monitor and needs review. Open the app for details.',
  data: { type: 'escalation', report_id: report.$id },
});

/** Admin alerts are deliberate public broadcasts, so their text is sent. */
export function adminAlertNotification(alert) {
  const title = clampText(alert.title, ADMIN_ALERT_TITLE_MAX) || 'Alert';
  const body = clampText(alert.message, ADMIN_ALERT_BODY_MAX) || title;
  return {
    title,
    body,
    data: {
      type: 'admin_alert',
      alert_id: alert.$id,
      severity: ALERT_SEVERITIES.has(alert.severity) ? alert.severity : null,
    },
  };
}

/**
 * Where an admin alert goes.
 *
 * OneSignal had tags; Appwrite has topics, and Phase 3 found the mapping
 * is one topic per targetable group — which is why there are ~650 of them
 * and why the tier question matters. The three shapes the database stores
 * are unchanged:
 *
 *   state NULL, lga 'All'  -> everyone
 *   state S,    lga 'All'  -> every LGA of S
 *   state S,    lga X      -> X in S only (Obi exists in two states)
 *
 * A fourth — an LGA with no state — is rejected by the check constraint
 * `alerts_target_lga_needs_state` and is unreachable from `alerts`. It is
 * still handled, so a hand-built row degrades to a name-only match
 * instead of throwing.
 */
export function alertTopics(alert) {
  const lga = String(alert?.targetLga ?? '').trim();
  const state = String(alert?.targetState ?? '').trim();
  const allLgas = !lga || lga.toLowerCase() === 'all';
  if (!state) {
    return allLgas ? { all: true, topics: [] } : { all: false, topics: [topicId('lga', lga)] };
  }
  if (allLgas) return { all: false, topics: [topicId('state', state)] };
  // Both must match, and a topic cannot express AND — so the LGA topic is
  // the state-scoped one. That is what makes them distinct for Obi in
  // Benue and Obi in Nasarawa, which share a name and nothing else.
  return { all: false, topics: [topicId('lga', `${state}-${lga}`)] };
}

/** A topic id: lower-case, hyphenated, and within Appwrite's 36 characters. */
export function topicId(kind, name) {
  const slug = String(name ?? '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
  const id = `${kind}-${slug}`;
  return id.length <= 36 ? id : `${kind}-${slug.slice(0, 34 - kind.length)}`;
}
