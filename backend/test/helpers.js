import { silentLog } from '../src/log.js';

export const logger = silentLog;

/** Records every push call instead of sending it. */
export function fakePush({ failOn } = {}) {
  const calls = [];
  const maybeFail = (kind) => {
    if (failOn === kind) throw new Error(`push ${kind} failed`);
  };
  return {
    calls,
    async sendToUsers(ids, n, opts = {}) {
      maybeFail('users');
      calls.push({ kind: 'users', ids, n, key: opts.key });
      return { sent: ids.length ? 1 : 0 };
    },
    async sendToTag(tagKey, tagValue, n, opts = {}) {
      maybeFail('tag');
      calls.push({ kind: 'tag', tagKey, tagValue, andTags: opts.andTags, n, key: opts.key });
      return { sent: 1 };
    },
    async sendToTags(tags, n, opts = {}) {
      maybeFail('tags');
      calls.push({ kind: 'tags', tags, n, key: opts.key });
      return { sent: 1 };
    },
    async sendToAll(n, opts = {}) {
      maybeFail('all');
      calls.push({ kind: 'all', n, key: opts.key });
      return { sent: 1 };
    },
  };
}

/** In-memory repo with the same interface as src/repo.js. */
export function fakeRepo({
  reports = [],
  alerts = [],
  profiles = [],
  events = [],
  escalations = [],
  authorities = [],
  settings = {},
  smsDeliveries = [],
  now = Date.now,
} = {}) {
  const state = { reports, alerts, profiles, events, escalations, authorities, settings, smsDeliveries, profileQueries: [], authorityQueries: [] };
  return {
    state,
    async claimOutboxEvents(limit) {
      const due = state.events.filter((e) => !e.processed_at).slice(0, limit);
      due.forEach((e) => (e.attempts = (e.attempts ?? 0) + 1));
      return due.map((e) => ({ ...e }));
    },
    async markEventProcessed(id, note = null) {
      const e = state.events.find((x) => x.id === id);
      e.processed_at = 'now';
      e.last_error = note;
    },
    async markEventFailed(id, message) {
      state.events.find((x) => x.id === id).last_error = message;
    },
    async getReport(id) {
      return state.reports.find((r) => r.id === id) ?? null;
    },
    async getAlert(id) {
      return state.alerts.find((a) => a.id === id) ?? null;
    },
    async setAuthBan(userId, banned) {
      state.bans ??= {};
      if (state.missingAuthUsers?.includes(userId)) return false;
      state.bans[userId] = banned;
      return true;
    },
    async getProfile(id) {
      return state.profiles.find((p) => p.id === id) ?? null;
    },
    async findProfiles(q) {
      state.profileQueries.push(q);
      return state.profiles
        .filter(
          (p) =>
            q.roles.includes(p.role) &&
            p.is_approved &&
            !p.is_disabled &&
            (q.lga == null || p.lga === q.lga) &&
            (q.ward == null || p.ward === q.ward) &&
            p.id !== q.excludeId,
        )
        .slice(0, q.limit);
    },
    async dueEscalations(limit, now = new Date().toISOString()) {
      return state.escalations
        .filter((e) => e.status === 'pending' && (e.escalate_at ?? '') <= now)
        .sort((a, b) => (a.escalate_at ?? '').localeCompare(b.escalate_at ?? ''))
        .slice(0, limit)
        .map((e) => ({ ...e }));
    },
    async finishEscalation(id, status, reason = null) {
      const e = state.escalations.find((x) => x.id === id);
      if (e.status !== 'pending') return false;
      Object.assign(e, { status, reason, processed_at: 'now' });
      return true;
    },
    async noteEscalationError(id, message, retryAt = null) {
      const e = state.escalations.find((x) => x.id === id);
      if (e.status !== 'pending') return;
      e.reason = message;
      if (retryAt) e.escalate_at = retryAt;
    },
    async getSettings(keys) {
      return Object.fromEntries(keys.filter((k) => k in state.settings).map((k) => [k, state.settings[k]]));
    },
    // Mirrors repo.findAuthorities: (coverage_state = state or coverage_state
    // is null). The NULL half is unreachable from a real database since
    // 20260927090000 made coverage_state NOT NULL; it stays here so the
    // defensive branch can be exercised.
    async findAuthorities(lga, reportState, limit) {
      state.authorityQueries.push({ lga, state: reportState, limit });
      const st = typeof reportState === 'string' ? reportState.trim() : '';
      return state.authorities
        .filter((a) => a.coverage_lga === lga && (a.coverage_state == null || (st && a.coverage_state === st)))
        .slice(0, limit);
    },
    async countAuthorities() {
      return state.authorities.length;
    },
    // sms_deliveries: unique (report_id, phone); created_at from `now`.
    async claimSmsDelivery({ reportId, phone, lga, state: st }) {
      if (state.smsFailClaim) throw new Error('claim failed');
      if (state.smsDeliveries.some((d) => d.report_id === reportId && d.phone === phone)) return false;
      state.smsDeliveries.push({ report_id: reportId, phone, lga: lga ?? '', state: st ?? '', status: 'claimed', created_at: new Date(now()).toISOString() });
      return true;
    },
    async setSmsDeliveryStatus(reportId, phone, status) {
      const d = state.smsDeliveries.find((x) => x.report_id === reportId && x.phone === phone);
      if (d) d.status = status;
    },
    async releaseSmsDelivery(reportId, phone) {
      state.smsDeliveries = state.smsDeliveries.filter((x) => !(x.report_id === reportId && x.phone === phone));
    },
    async countSmsDeliveries({ lga, state: st, since }) {
      return state.smsDeliveries.filter(
        (d) => d.lga === (lga ?? '') && d.state === (st ?? '') && d.status !== 'rejected' && d.created_at >= since,
      ).length;
    },
    async countReportSmsDeliveries(reportId) {
      return state.smsDeliveries.filter((d) => d.report_id === reportId && d.status !== 'rejected').length;
    },
    async finishPendingEscalationForReport(reportId, status, reason = null) {
      const rows = state.escalations.filter((e) => e.report_id === reportId && e.status === 'pending');
      rows.forEach((e) => Object.assign(e, { status, reason, processed_at: 'now' }));
      return rows.length > 0;
    },
    async markReportEscalated(reportId, reason) {
      const r = state.reports.find((x) => x.id === reportId);
      if (!r || r.status !== 'pending' || r.escalated) return false;
      Object.assign(r, { escalated: true, escalated_at: 'now', escalation_reason: reason, escalation_status: 'escalated' });
      return true;
    },
  };
}

export const profile = (id, role, extra = {}) => ({
  id,
  role,
  lga: 'Ikeja',
  ward: 'Ward 1',
  is_approved: true,
  is_disabled: false,
  ...extra,
});

/** Records SMS sends; `failFor` is a set of E.164 numbers (or true for all) that throw. */
export function fakeSms({ configured = true, failFor = null } = {}) {
  const sent = [];
  return {
    name: 'fake',
    configured,
    sent,
    async send(to, text) {
      if (failFor === true || failFor?.has?.(to)) throw new Error(`sms to ${to} failed`);
      sent.push({ to, text });
      return { id: `m${sent.length}` };
    },
  };
}

/** fetch stub: records calls and answers with `status`/`json`. */
export function fakeFetch({ status = 200, json = {} } = {}) {
  const calls = [];
  const fn = async (url, init) => {
    calls.push({ url, init });
    return { ok: status >= 200 && status < 300, status, json: async () => json };
  };
  fn.calls = calls;
  return fn;
}
