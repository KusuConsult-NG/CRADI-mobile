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
  listRows,
  Query,
  setAccountLabels,
  updateRow,
  updateRowsWhere,
  upsertRow,
} from './lib/appwrite.js';
import {
  ErrorType,
  Refusal,
  callerId,
  conflict,
  forbidden,
  staleWrite,
  handler,
  invalid,
  notFound,
  readJson,
} from './lib/http.js';
import {
  escalationTimeoutMinutes,
  getSettings,
  minimumPeerConfirmations,
} from './lib/settings.js';
import {
  RULES,
  WRITABLE,
  assertLocation,
  assertRole,
  LABEL_FIELDS,
  accountLabels,
  assertCoverage,
  assertTarget,
  isAdmin,
  reportContentChanged,
} from './lib/policy.js';

const OPS = new Set(['create', 'upsert', 'update', 'delete']);

/**
 * `report_has_votes(p_report_id)`: has anybody voted on this report?
 *
 * Any vote, confirming or disputing — a dispute is still somebody who
 * read the description that is about to change.
 *
 * A read that fails is treated as "there are votes". The alternative is
 * to let an edit through on a failed lookup, and this rule exists to
 * stop a report changing under the peers who voted on it.
 */
async function reportHasVotes(reportId) {
  const found = await listRows('verifications', [
    Query.equal('reportId', reportId),
    Query.limit(1),
  ]);
  if (!found.ok) return true;
  return (found.body?.total ?? 0) > 0;
}

export default handler(async ({ req, log }) => {
  const payload = readJson(req);
  const userId = callerId(req);

  const op = payload.op;
  const collection = payload.collection;
  const documentId = payload.documentId;
  const data = payload.data ?? {};
  // Optional optimistic lock on `update`; see where it is applied below.
  const expect = payload.expect ?? null;

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
    return writeProfile({ ...context, op, data, expect, log });
  }

  assertRole(role, rule.roles, `write ${collection}`);

  if (op === 'delete') {
    // Deletes are admin-only everywhere this Function serves. Nothing in
    // the app deletes a report or a vote; an admin clearing test data
    // does.
    if (!isAdmin(role)) throw forbidden('Only an administrator may delete this');
    // Read it first, because after the delete there is nothing left to
    // say which report the vote belonged to.
    const before = collection === 'verifications' ? await getRow(collection, documentId) : null;
    const deleted = await deleteRow(collection, documentId);
    if (deleted.status === 404) throw notFound();
    if (!deleted.ok) throw new Error(`delete failed: ${deleted.status}`);
    log(`deleted ${collection}/${documentId} by ${userId}`);
    if (before?.ok && before.body.reportId) {
      await countConfirmations(before.body.reportId, log);
    }
    return {};
  }

  if (op === 'update') {
    const current = await getRow(collection, documentId);
    if (current.status === 404) throw notFound();
    if (!current.ok) throw new Error(`read failed: ${current.status}`);
    assertUnchanged(rule.immutable, current.body, data);
    const clean = strip(data, rule, { keepImmutable: false, allow: rule.decidable });
    rule.guardUpdate?.({ role, userId, current: current.body, data: clean });
    // `report_has_votes`, the one rule in the guard that needs a read:
    // peers voted on what they saw, so the report cannot change under
    // them. Asked only when the patch is a content edit by a non-admin,
    // which the guard above has already established is the reporter's
    // own pending report.
    if (
      collection === 'reports' &&
      !isAdmin(role) &&
      reportContentChanged(current.body, clean) &&
      (await reportHasVotes(documentId))
    ) {
      throw forbidden('A report cannot be edited after peers have voted on it');
    }
    rule.derive?.(clean, { ...current.body, ...clean }, current.body);
    // Checked against the row as it will be, not against the patch: an edit
    // that moves the LGA without resending the state must not slip through.
    //
    // Both of these, not just coverage. `assertTarget` ran only on the
    // create branch, so the CHECK constraint it replaces
    // (`alerts_target_lga_needs_state`) held for a new alert and not for
    // an edited one — and an alert retargeted to an LGA with no state
    // goes to the wrong Obi, of which Nigeria has two.
    //
    // `requiresLocation` is deliberately not here: a report's state, LGA
    // and ward are `immutable`, so an update that changes them is already
    // refused by name, and re-validating the merged row would only ever
    // fail for a row that was written before the list it validates against.
    if (rule.requiresCoverage) assertCoverage({ ...current.body, ...clean });
    if (rule.requiresTarget) assertTarget({ ...current.body, ...clean });
    if (collection === 'reports' && 'status' in clean) {
      // Appwrite's event payload is the document, with no "before", so
      // the event Function cannot tell a status change from any other
      // edit. Recording what it was is the only way it can — see
      // `on-write.js`. Postgres got this from the trigger's OLD row.
      clean.previousStatus = current.body.status ?? null;
    }
    // `expect` is an optimistic lock: apply this edit only while the
    // named fields still hold the values the caller saw. The admin panel
    // decides a report from a card that may be minutes old, and
    // overwriting somebody else's decision silently is the failure this
    // prevents. Checked by the server in one call rather than against
    // the row read above, which would be a race with its own name.
    if (expect && Object.keys(expect).length > 0) {
      const queries = [
        Query.equal('$id', documentId),
        ...Object.entries(expect).map(([field, value]) =>
          value === null ? Query.isNull(field) : Query.equal(field, value),
        ),
      ];
      const applied = await updateRowsWhere(collection, queries, clean);
      if (!applied.ok) refuseWrite('update', applied);
      if ((applied.body?.total ?? 0) === 0) {
        throw staleWrite();
      }
      log(`updated ${collection}/${documentId} by ${userId} (expected ${JSON.stringify(expect)})`);
      const after = await getRow(collection, documentId);
      return { document: after.ok ? after.body : { ...current.body, ...clean } };
    }

    const updated = await updateRow(collection, documentId, clean);
    if (!updated.ok) refuseWrite('update', updated);
    log(`updated ${collection}/${documentId} by ${userId}`);
    return { document: updated.body };
  }

  // create / upsert
  const stamped = { ...strip(data, rule, { keepImmutable: true }), ...(rule.create?.(context) ?? {}) };
  if (rule.requiresTarget) assertTarget(stamped);
  if (rule.requiresCoverage) assertCoverage(stamped);
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
  if (!written.ok) refuseWrite(op, written);
  if (collection === 'reports' && op !== 'update') {
    await scheduleEscalation(written.body, log);
  }
  if (collection === 'verifications') {
    await countConfirmations(written.body.reportId, log);
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
async function writeProfile({ op, userId, documentId, data, expect, role, log }) {
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
  // The same optimistic lock the other collections get: the admin panel
  // pins the role, LGA and ward it reviewed, so a profile edited in
  // another tab is refused rather than silently overwritten.
  if (expect && Object.keys(expect).length > 0) {
    const queries = [
      Query.equal('$id', documentId),
      ...Object.entries(expect).map(([field, value]) =>
        value === null ? Query.isNull(field) : Query.equal(field, value),
      ),
    ];
    const applied = await updateRowsWhere('profiles', queries, data);
    if (!applied.ok) refuseWrite('profile update', applied);
    if ((applied.body?.total ?? 0) === 0) {
      const exists = await getRow('profiles', documentId);
      if (exists.status === 404) throw notFound();
      throw staleWrite();
    }
    log(`profile ${documentId} updated by ${userId} (expected ${JSON.stringify(expect)})`);
    const after = await getRow('profiles', documentId);
    const document = after.ok ? after.body : { $id: documentId, ...data };
    await syncLabels(documentId, data, document, log);
    return { document };
  }

  const updated = await updateRow('profiles', documentId, data);
  if (updated.status === 404) throw notFound();
  if (!updated.ok) refuseWrite('profile update', updated);
  log(`profile ${documentId} updated by ${userId}`);
  await syncLabels(documentId, data, updated.body, log);
  return { document: updated.body };
}

/**
 * Puts the account's labels back in step with the profile row.
 *
 * `role`, `isApproved` and `isDisabled` are the inputs to every
 * `read("label:…")` ACL, and a label lives on the account rather than on
 * the row — so until this ran, promoting someone in the admin panel
 * changed what the row said and nothing about what they could read. The
 * failure was silent: Appwrite answers an unreadable collection with
 * `200 {"total": 0}`, so a new admin saw an empty panel and no error.
 *
 * Only called when one of those fields was in the patch, and never fatal:
 * the row is already written, and failing the whole call here would
 * report a write that happened as one that did not. A mismatch is logged
 * loudly instead, and the reconciling sweep is where a repair belongs.
 */
async function syncLabels(documentId, patch, document, log) {
  if (!LABEL_FIELDS.some((field) => field in patch)) return;
  const labels = accountLabels(document ?? {});
  const result = await setAccountLabels(documentId, labels);
  if (result.ok) {
    log(`labels for ${documentId}: [${labels.join(', ')}]`);
    return;
  }
  log(
    `WARNING: profile ${documentId} was updated but its account labels were not ` +
      `(${result.status} ${result.body?.message ?? ''}). It now says ` +
      `${JSON.stringify(labels)} and the account does not — that account reads ` +
      'nothing those labels grant.',
  );
}

/**
 * Counts a report's confirmations and verifies it once enough peers agree.
 *
 * This is `verifications_after_insert`, which had no Appwrite
 * counterpart: between Phase 1 and Phase 23 a vote was stored and
 * nothing read it, so `reports.verificationCount` stayed 0, no report
 * ever reached `verified` on its own, and `minimum_peer_confirmations`
 * — a setting the admin panel offers and explains — did nothing at all.
 *
 * Counted rather than incremented, for the same reason the trigger
 * counted: an increment is only correct if every vote it ever saw was
 * applied exactly once, and this runs after a network call that can be
 * retried. A count is idempotent and self-repairing.
 *
 * The flip to `verified` is a compare-and-set on `status = 'pending'`,
 * which is the trigger's `where id = ... and status = 'pending'` and
 * carries the same two properties: it happens exactly once however many
 * votes arrive after the threshold, and it never overwrites a decision
 * an admin has already made.
 *
 * Postgres serialised concurrent confirmations with `for update`;
 * Appwrite has no row lock, so two votes landing together can both read
 * the lower count. The count is self-correcting on the next vote, and
 * `reconcile.js` repairs a report left short of its own votes.
 */
async function countConfirmations(reportId, log) {
  if (!reportId) return;
  const counted = await listRows('verifications', [
    Query.equal('reportId', reportId),
    Query.equal('isConfirmed', true),
    Query.limit(1),
  ]);
  if (!counted.ok) {
    // The vote is already stored. Failing the call now would tell the
    // verifier their confirmation did not land, and they would send it
    // again — against a unique index, so the retry would be refused too.
    log(`WARNING: could not count confirmations for ${reportId}: ${counted.status}`);
    return;
  }
  const confirmed = counted.body.total ?? 0;
  const updated = await updateRow('reports', reportId, { verificationCount: confirmed });
  if (!updated.ok) {
    log(`WARNING: could not store verificationCount=${confirmed} for ${reportId}: ${updated.status}`);
    return;
  }

  const settings = await getSettings();
  const threshold = minimumPeerConfirmations(settings);
  if (confirmed < threshold) {
    log(`report ${reportId}: ${confirmed}/${threshold} confirmations`);
    return;
  }

  const verified = await updateRowsWhere(
    'reports',
    [Query.equal('$id', reportId), Query.equal('status', 'pending')],
    {
      status: 'verified',
      verifiedAt: new Date().toISOString(),
      autoValidated: true,
      // So the event Function can tell this was a status change and
      // announce it; Appwrite's event payload has no "before".
      previousStatus: 'pending',
    },
  );
  if (!verified.ok) {
    log(`WARNING: could not verify ${reportId} at ${confirmed}/${threshold}: ${verified.status}`);
    return;
  }
  log(
    (verified.body?.total ?? 0) > 0
      ? `report ${reportId} verified by ${confirmed} peers (threshold ${threshold})`
      : `report ${reportId} reached ${confirmed}/${threshold} but was already decided`,
  );
}

/**
 * Turns Appwrite's refusal of a row write into the caller's refusal.
 *
 * A **400** here is the payload's fault — a column that does not exist, a
 * value of the wrong type, a string past its size — and Appwrite names it
 * exactly: `Invalid document structure: Unknown attribute: "updated_by"`.
 * Collapsing that into a 500 threw the reason away. It cost real time
 * during the admin panel's migration, where the in-memory mock reported
 * the attribute by name and the real server answered "The server could
 * not complete that": the fake was the more useful of the two, which is
 * the wrong way round.
 *
 * Anything else stays a fault. A 401 or 403 here is **this Function's**
 * API key lacking a scope, not the caller's mistake, and repeating
 * "missing scope (users.write)" to a field agent would be both confusing
 * and a detail they should not be given.
 */
function refuseWrite(what, response) {
  const message = response.body?.message;
  if (response.status === 400 && message) {
    throw new Refusal(400, message, response.body?.type ?? ErrorType.invalid);
  }
  throw new Error(`${what} failed: ${response.status} ${message ?? ''}`);
}

/** Removes the fields the server owns, so a round-tripped document is safe. */
export function strip(data, rule, { keepImmutable, allow }) {
  const owned = new Set(rule.serverOwned ?? []);
  // Fields the server owns *at creation* but a reviewer may change
  // afterwards — a report's status is stamped `pending` and no client may
  // claim otherwise, yet approving one is the whole job of the panel.
  // Without this they were stripped from the update too, so an approval
  // returned 200 and changed nothing.
  const allowed = new Set(allow ?? []);
  const out = {};
  for (const [key, value] of Object.entries(data)) {
    if (key.startsWith('$') || key === 'id') continue;
    if (owned.has(key) && !allowed.has(key)) continue;
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
