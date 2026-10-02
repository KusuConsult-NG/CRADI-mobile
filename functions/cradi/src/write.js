/**
 * `write` — the collections the client may not write directly.
 *
 * Contract: docs/APPWRITE-FUNCTION-CONTRACTS.md.
 * Client: lib/core/services/appwrite/appwrite_data_backend.dart.
 *
 * The generalisation of the spike's `create-report`, which Phase 4 proved:
 * the collection is closed to clients, so this is the only way a report is
 * created, and a client that sends `status:"approved"` gets a 201 and a
 * document that still says `pending`.
 */
import {
  databaseId,
  ensureWardTeam,
  createRow,
  deleteRow,
  getRow,
  updateRow,
  upsertRow,
} from './lib/appwrite.js';
import {
  ErrorType,
  Refusal,
  callerId,
  conflict,
  forbidden,
  handler,
  invalid,
  notFound,
  readJson,
} from './lib/http.js';
import { escalationTimeoutMinutes, getSettings } from './lib/settings.js';
import {
  RULES,
  WRITABLE,
  assertLocation,
  assertRole,
  assertTarget,
  isAdmin,
} from './lib/policy.js';

const OPS = new Set(['create', 'upsert', 'update', 'delete']);

export default handler(async ({ req, log }) => {
  const payload = readJson(req);
  const userId = callerId(req);

  const op = payload.op;
  const collection = payload.collection;
  const documentId = payload.documentId;
  const data = payload.data ?? {};

  if (!OPS.has(op)) throw invalid(`Unknown op: ${op}`, ErrorType.argument);
  if (!WRITABLE.has(collection)) {
    throw forbidden(`${collection} is not writable through this Function`);
  }
  if (!documentId) throw invalid('documentId is required', ErrorType.argument);

  // One line, before anything can fail, naming who and what. Appwrite
  // only shows a Function's logs to an API key, so this is not visible
  // to the caller — and without it a refusal is indistinguishable from
  // a misrouted request.
  log(`write ${op} ${collection}/${documentId} by ${userId}`);

  // is_enabled_user(): the profile decides, never the client.
  const profileResponse = await getRow('profiles', userId);
  if (profileResponse.status === 404) {
    // Says which database and what the server replied: a 404 here is
    // "no such profile", "no such table" and "wrong database" alike,
    // and the caller-facing message deliberately does not distinguish
    // them.
    log(
      `profile ${userId} not found in ${databaseId()}: ` +
        `${JSON.stringify(profileResponse.body).slice(0, 200)}`,
    );
    throw forbidden('Your account is not set up yet');
  }
  if (!profileResponse.ok) {
    throw new Error(`profile read failed: ${profileResponse.status}`);
  }
  const profile = profileResponse.body;
  if (profile.isDisabled === true) {
    // No `type`, so the client shows this wording to the user — which is
    // the whole reason a disabled agent sees "Your account has been
    // disabled" rather than "Something went wrong".
    throw forbidden('Your account has been disabled. Please contact support.');
  }

  const rule = RULES[collection] ?? {};
  const role = profile.role ?? 'user';
  const context = { userId, profile, role, documentId, collection };

  if (collection === 'profiles') {
    return writeProfile({ ...context, op, data, log });
  }

  assertRole(role, rule.roles, `write ${collection}`);

  if (op === 'delete') {
    // Deletes are admin-only everywhere this Function serves. Nothing in
    // the app deletes a report or a vote; an admin clearing test data
    // does.
    if (!isAdmin(role)) throw forbidden('Only an administrator may delete this');
    const deleted = await deleteRow(collection, documentId);
    if (deleted.status === 404) throw notFound();
    if (!deleted.ok) throw new Error(`delete failed: ${deleted.status}`);
    log(`deleted ${collection}/${documentId} by ${userId}`);
    return {};
  }

  if (op === 'update') {
    const current = await getRow(collection, documentId);
    if (current.status === 404) throw notFound();
    if (!current.ok) throw new Error(`read failed: ${current.status}`);
    assertUnchanged(rule.immutable, current.body, data);
    const clean = strip(data, rule, { keepImmutable: false });
    if (collection === 'reports' && 'status' in clean) {
      // Appwrite's event payload is the document, with no "before", so
      // the event Function cannot tell a status change from any other
      // edit. Recording what it was is the only way it can — see
      // `on-write.js`. Postgres got this from the trigger's OLD row.
      clean.previousStatus = current.body.status ?? null;
    }
    const updated = await updateRow(collection, documentId, clean);
    if (!updated.ok) throw new Error(`update failed: ${updated.status}`);
    log(`updated ${collection}/${documentId} by ${userId}`);
    return { document: updated.body };
  }

  // create / upsert
  const stamped = { ...strip(data, rule, { keepImmutable: true }), ...(rule.create?.(context) ?? {}) };
  if (rule.requiresTarget) assertTarget(stamped);
  if (rule.requiresLocation) {
    assertLocation(stamped);
    // The ACL names a team, so the team has to exist before the document
    // that points at it — otherwise the write succeeds and nobody in the
    // ward can read it.
    await ensureWardTeam(stamped.state, stamped.lga, stamped.ward);
  }
  if (collection === 'verifications') {
    await stampReportLocation(stamped);
    await ensureWardTeam(stamped.state, stamped.lga, stamped.ward);
  }

  const permissions = rule.acl?.({ ...context, data: stamped });
  const written =
    op === 'upsert'
      ? await upsertRow(collection, documentId, stamped, permissions)
      : await createRow(collection, documentId, stamped, permissions);

  if (written.status === 409) throw conflict('That has already been submitted');
  if (!written.ok) {
    throw new Error(`${op} failed: ${written.status} ${written.body?.message}`);
  }
  if (collection === 'reports' && op !== 'update') {
    await scheduleEscalation(written.body, log);
  }

  log(`${op}d ${collection}/${written.body.$id} by ${userId} in ${databaseId()}`);
  return { document: written.body };
});

/**
 * Queues the report's escalation deadline.
 *
 * A Postgres trigger inserted this row in the same transaction as the
 * report. Here it is one more call in the write Function — which is the
 * right place despite not being transactional: the alternative is the
 * event Function, and Phase 6 measured that those run once and are never
 * retried. A failure here fails the whole write and the client retries,
 * which is far better than a report that quietly never escalates.
 *
 * The id is the report's, so a retried write collides rather than
 * queueing the same deadline twice.
 */
async function scheduleEscalation(report, log) {
  const settings = await getSettings();
  const minutes = escalationTimeoutMinutes(settings);
  const created = await createRow('scheduled_escalations', report.$id, {
    reportId: report.$id,
    escalateAt: new Date(Date.now() + minutes * 60_000).toISOString(),
    status: 'pending',
    reason: null,
    processedAt: null,
  });
  if (created.status === 409) return;
  if (!created.ok) {
    throw new Error(`escalation schedule failed: ${created.status}`);
  }
  log(`escalation for ${report.$id} queued in ${minutes}m`);
}

/**
 * A verification's ward comes from the report, not from the client.
 *
 * Phase 1 denormalises it so the read path never needs a join; getting it
 * from the caller would let an EWM vote on another ward's report by
 * claiming it was theirs, which is exactly the cross-collection check the
 * old `verifications_insert` policy made.
 */
async function stampReportLocation(data) {
  if (!data.reportId) throw invalid('reportId is required', ErrorType.argument);
  const report = await getRow('reports', data.reportId);
  if (report.status === 404) throw notFound('That report no longer exists');
  if (!report.ok) throw new Error(`report read failed: ${report.status}`);
  if (report.body.status !== 'pending') {
    // 22023 in the old world: it exists, but not in a state that allows
    // this. The client's `invalidState` is reserved for exactly this.
    throw new Refusal(409, 'That report is no longer open for votes');
  }
  data.state = report.body.state;
  data.lga = report.body.lga;
  data.ward = report.body.ward;
}

/** Fields nobody but an admin may edit on a profile. */
function writeProfile({ op, userId, documentId, data, role, log }) {
  if (op === 'delete') throw forbidden('Profiles are not deleted here');
  const rule = RULES.profiles;
  const own = documentId === userId;
  if (!own && !isAdmin(role)) {
    throw forbidden('You may only edit your own profile');
  }
  const allowed = isAdmin(role)
    ? [...rule.selfWritable, ...rule.adminWritable]
    : rule.selfWritable;
  const rejected = Object.keys(data).filter((k) => !allowed.includes(k));
  if (rejected.length > 0) {
    // Refused rather than ignored: somebody asking to approve themselves
    // must not get a 200 and believe it worked.
    throw forbidden(`You may not change: ${rejected.join(', ')}`);
  }
  return updateRow('profiles', documentId, data).then((updated) => {
    if (updated.status === 404) throw notFound();
    if (!updated.ok) throw new Error(`profile update failed: ${updated.status}`);
    log(`profile ${documentId} updated by ${userId}`);
    return { document: updated.body };
  });
}

/** Removes the fields the server owns, so a round-tripped document is safe. */
export function strip(data, rule, { keepImmutable }) {
  const owned = new Set(rule.serverOwned ?? []);
  const out = {};
  for (const [key, value] of Object.entries(data)) {
    if (key.startsWith('$') || key === 'id') continue;
    if (owned.has(key)) continue;
    if (!keepImmutable && rule.immutable?.includes(key)) continue;
    out[key] = value;
  }
  return out;
}

/** An update may not move a document between wards, or change its owner. */
export function assertUnchanged(immutable, current, data) {
  for (const field of immutable ?? []) {
    if (!(field in data)) continue;
    if (data[field] === current[field]) continue;
    throw forbidden(`${field} cannot be changed after it is set`);
  }
}
