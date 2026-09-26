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
      calls.push({ kind: 'tag', tagKey, tagValue, n, key: opts.key });
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
} = {}) {
  const state = { reports, alerts, profiles, events, escalations, authorities, settings, profileQueries: [], authorityQueries: [] };
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
    async findAuthorities(lga, limit) {
      state.authorityQueries.push({ lga, limit });
      return state.authorities.filter((a) => a.coverage_lga === lga).slice(0, limit);
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
