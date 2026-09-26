// Data access over supabase-js (service role, bypasses RLS). Everything the
// worker/cron/API needs from the database goes through here so the logic can
// be tested with an in-memory fake.

const REPORT_COLUMNS =
  'id, user_id, hazard_type, severity, ward, lga, state, description, status, rejection_reason, escalated, escalation_reason';
const ALERT_COLUMNS = 'id, title, message, severity, target_lga, target_state, is_active';

/** Double-quotes a value for a PostgREST `or=(...)` filter (commas, dots, parens are reserved). */
function postgrestQuote(value) {
  return `"${String(value).replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;
}

function check({ data, error }, what) {
  if (error) throw new Error(`${what}: ${error.message ?? error}`);
  return data;
}

export function createRepo(supabase) {
  return {
    async claimOutboxEvents(limit) {
      return check(await supabase.rpc('claim_outbox_events', { p_limit: limit }), 'claim_outbox_events') ?? [];
    },

    async markEventProcessed(id, note = null) {
      check(
        await supabase
          .from('notification_outbox')
          .update({ processed_at: new Date().toISOString(), last_error: note })
          .eq('id', id),
        'mark processed',
      );
    },

    async markEventFailed(id, message) {
      check(
        await supabase
          .from('notification_outbox')
          .update({ last_error: String(message).slice(0, 1000) })
          .eq('id', id),
        'mark failed',
      );
    },

    async getReport(id) {
      return check(
        await supabase.from('reports').select(REPORT_COLUMNS).eq('id', id).maybeSingle(),
        'load report',
      );
    },

    async getAlert(id) {
      return check(
        await supabase.from('alerts').select(ALERT_COLUMNS).eq('id', id).maybeSingle(),
        'load alert',
      );
    },

    /** Approved, enabled profiles matching { roles, lga?, ward?, excludeId?, limit }. */
    async findProfiles({ roles, lga, ward, excludeId, limit = 50 }) {
      let q = supabase
        .from('profiles')
        .select('id, role, is_approved, is_disabled')
        .in('role', roles)
        .eq('is_approved', true)
        .eq('is_disabled', false);
      if (lga != null) q = q.eq('lga', lga);
      if (ward != null) q = q.eq('ward', ward);
      if (excludeId) q = q.neq('id', excludeId);
      return check(await q.limit(limit), 'find profiles') ?? [];
    },

    /**
     * Applies or lifts the Supabase Auth ban for a user so sign-in matches
     * profiles.is_disabled. Returns false when the auth user doesn't exist.
     */
    async setAuthBan(userId, banned) {
      const { error } = await supabase.auth.admin.updateUserById(userId, {
        ban_duration: banned ? '876000h' : 'none',
      });
      if (!error) return true;
      if (error.status === 404 || /not.?found/i.test(error.message ?? '')) return false;
      throw new Error(`update auth ban: ${error.message}`);
    },

    async getProfile(id) {
      return check(
        await supabase
          .from('profiles')
          .select('id, email, role, is_approved, is_disabled')
          .eq('id', id)
          .maybeSingle(),
        'load profile',
      );
    },

    async dueEscalations(limit) {
      return (
        check(
          await supabase
            .from('scheduled_escalations')
            .select('id, report_id, escalate_at, reason')
            .eq('status', 'pending')
            .lte('escalate_at', new Date().toISOString())
            .order('escalate_at', { ascending: true })
            .limit(limit),
          'due escalations',
        ) ?? []
      );
    },

    /** Conditional (status='pending') so concurrent instances cannot both finish it. Returns true if this call won. */
    async finishEscalation(id, status, reason = null) {
      const rows = check(
        await supabase
          .from('scheduled_escalations')
          .update({ status, reason, processed_at: new Date().toISOString() })
          .eq('id', id)
          .eq('status', 'pending')
          .select('id'),
        'finish escalation',
      );
      return (rows ?? []).length > 0;
    },

    /** Records a failure on a still-pending escalation; `retryAt` (ISO) reschedules it. */
    async noteEscalationError(id, message, retryAt = null) {
      const patch = { reason: String(message).slice(0, 500) };
      if (retryAt) patch.escalate_at = retryAt;
      check(
        await supabase
          .from('scheduled_escalations')
          .update(patch)
          .eq('id', id)
          .eq('status', 'pending'),
        'note escalation error',
      );
    },

    /** app_settings values (jsonb) for `keys`, as { key: value }; missing keys are absent. */
    async getSettings(keys) {
      const rows = check(
        await supabase.from('app_settings').select('key, value').in('key', keys),
        'load app settings',
      );
      return Object.fromEntries((rows ?? []).map((r) => [r.key, r.value]));
    },

    /**
     * Authorities covering the report's LGA: coverage_lga equals `lga` (exact
     * match, as stored on the report) and coverage_state equals `state` or is
     * NULL (legacy rows that predate coverage_state match by LGA name only).
     * LGA names repeat across states (Obi: Benue and Nasarawa), so a report
     * with a state never reaches another state's same-named LGA. An empty
     * `state` matches only rows with no coverage_state (it can't tell which
     * state's same-named LGA is meant).
     */
    async findAuthorities(lga, state, limit) {
      let q = supabase
        .from('authorities')
        .select('id, name, organization, phone, coverage_lga, coverage_state')
        .eq('coverage_lga', lga);
      const st = typeof state === 'string' ? state.trim() : '';
      if (st) q = q.or(`coverage_state.eq.${postgrestQuote(st)},coverage_state.is.null`);
      else q = q.is('coverage_state', null);
      return (
        check(await q.order('created_at', { ascending: true }).limit(limit), 'find authorities') ?? []
      );
    },

    /**
     * Claims (report, phone) in sms_deliveries before texting it. Returns
     * false when a row already exists (sent, rejected or in flight).
     */
    async claimSmsDelivery({ reportId, phone, lga, state }) {
      const rows = check(
        await supabase
          .from('sms_deliveries')
          .upsert(
            { report_id: reportId, phone, lga: lga ?? '', state: state ?? '', status: 'claimed' },
            { onConflict: 'report_id,phone', ignoreDuplicates: true },
          )
          .select('id'),
        'claim sms delivery',
      );
      return (rows ?? []).length > 0;
    },

    async setSmsDeliveryStatus(reportId, phone, status) {
      check(
        await supabase.from('sms_deliveries').update({ status }).eq('report_id', reportId).eq('phone', phone),
        'update sms delivery',
      );
    },

    /** Drops a claim after a retryable failure so a retry sends again. */
    async releaseSmsDelivery(reportId, phone) {
      check(
        await supabase.from('sms_deliveries').delete().eq('report_id', reportId).eq('phone', phone),
        'release sms delivery',
      );
    },

    /** Texts (claimed or sent) for (lga, state) created at or after `since` (ISO). */
    async countSmsDeliveries({ lga, state, since }) {
      const { count, error } = await supabase
        .from('sms_deliveries')
        .select('id', { count: 'exact', head: true })
        .eq('lga', lga ?? '')
        .eq('state', state ?? '')
        .neq('status', 'rejected')
        .gte('created_at', since);
      if (error) throw new Error(`count sms deliveries: ${error.message ?? error}`);
      return count ?? 0;
    },

    /** Texts (claimed or sent) for one report. */
    async countReportSmsDeliveries(reportId) {
      const { count, error } = await supabase
        .from('sms_deliveries')
        .select('id', { count: 'exact', head: true })
        .eq('report_id', reportId)
        .neq('status', 'rejected');
      if (error) throw new Error(`count report sms deliveries: ${error.message ?? error}`);
      return count ?? 0;
    },

    /** Finishes the report's pending scheduled escalation (if any). Returns true if a row was updated. */
    async finishPendingEscalationForReport(reportId, status, reason = null) {
      const rows = check(
        await supabase
          .from('scheduled_escalations')
          .update({ status, reason, processed_at: new Date().toISOString() })
          .eq('report_id', reportId)
          .eq('status', 'pending')
          .select('id'),
        'finish report escalation',
      );
      return (rows ?? []).length > 0;
    },

    /** Flags a still-pending, not-yet-escalated report. Status stays 'pending'. */
    async markReportEscalated(reportId, reason) {
      const rows = check(
        await supabase
          .from('reports')
          .update({
            escalated: true,
            escalated_at: new Date().toISOString(),
            escalation_reason: reason,
            escalation_status: 'escalated',
          })
          .eq('id', reportId)
          .eq('status', 'pending')
          .eq('escalated', false)
          .select('id'),
        'escalate report',
      );
      return (rows ?? []).length > 0;
    },
  };
}
