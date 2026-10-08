/**
 * What the client does not get to decide.
 *
 * Phase 1 found 14 of 19 collections have a rule an ACL cannot express.
 * This is where those rules live now, and Phase 4's third row is the one
 * that matters: a client sending `status:"approved", verificationCount:99`
 * got a `201` and a stored document still reading `status: "pending"`.
 *
 * Two mechanisms, and the difference is deliberate:
 *
 * - `serverOwned` is **silently overwritten**. The client may send it; it
 *   is simply replaced. These are fields a well-behaved client sets by
 *   accident (round-tripping a document it read), so refusing would break
 *   ordinary edits for no gain.
 * - `immutable` may not be *changed* once set. An update that tries is
 *   refused rather than ignored, because a caller asking to move a report
 *   to another ward needs to know it did not happen.
 */

import { ErrorType, forbidden, invalid } from './http.js';
import { wardTeam } from './appwrite.js';
import locations from '../data/locations.json' with { type: 'json' };

/** Collections this Function will write. Anything else is refused. */
export const WRITABLE = new Set([
  'profiles',
  'reports',
  'verifications',
  'verification_overrides',
  'alerts',
  'authorities',
  'knowledge_base',
  'news_links',
  'app_settings',
]);

/** Roles, as stored in `profiles.role`. */
const STAFF = ['ewm', 'ewv', 'ewr', 'ldp_coordinator', 'project_staff'];
const ADMIN = ['admin', 'tech_support'];
const VERIFIER = ['ewm', 'ewv', 'ewr', 'admin'];

/**
 * Per-collection rules.
 *
 * - `serverOwned` — stripped from whatever the client sent, then set by
 *   `create`. Listed separately rather than derived from `create`'s
 *   output, so the strip does not depend on calling it with a fake
 *   context; `policy.test.js` asserts the two agree.
 * - `create(ctx)` — the values the server stamps on.
 * - `roles` — who may write here at all.
 * - `immutable` — fields an update may not change (refused, not ignored).
 * - `acl` — the document's permissions.
 */
export const RULES = {
  reports: {
    serverOwned: ['userId', 'userName', 'userRole', 'status',
                  'verificationCount', 'escalated', 'previousStatus'],
    create: ({ userId, profile }) => ({
      userId,
      // Denormalised at creation, per Phase 1: the report list shows who
      // filed it and Appwrite cannot join to find out.
      userName: profile.name ?? '',
      userRole: profile.role ?? 'user',
      status: 'pending',
      verificationCount: 0,
      escalated: false,
    }),
    immutable: ['userId', 'state', 'lga', 'ward'],
    /**
     * Server-owned at creation, but a reviewer decides them afterwards.
     * `guardUpdate` below says who, field by field.
     */
    decidable: [
      'status', 'approvedAt', 'rejectedAt', 'rejectionReason',
      'verifiedAt', 'verificationCount', 'autoValidated',
      'escalated', 'escalatedAt', 'escalationStatus',
      'updatedBy', 'severity', 'isAlert',
    ],
    guardUpdate: guardReportUpdate,
    derive: (clean, merged, current = {}) => {
      // Postgres set this on insert *and* update; nothing else does, so
      // without it a report raised to `critical` never became an alert.
      if ('severity' in clean) clean.isAlert = ALERT_SEVERITIES.includes(merged.severity);
      // `guard_report_update`'s last block, which ran for every writer
      // including the triggers: the decision columns follow the status.
      // Without it an approved report keeps the rejection reason it was
      // turned down with, and the app shows both.
      if ('status' in clean && clean.status !== (current.status ?? null)) {
        const now = new Date().toISOString();
        if (clean.status === 'approved') {
          clean.approvedAt ??= now;
          clean.rejectedAt = null;
          clean.rejectionReason = null;
        } else if (clean.status === 'rejected') {
          clean.rejectedAt ??= now;
          clean.approvedAt = null;
        } else if (clean.status === 'verified') {
          clean.verifiedAt ??= now;
          clean.approvedAt = null;
          clean.rejectedAt = null;
          clean.rejectionReason = null;
        }
      }
    },
    requiresLocation: true,
    acl: ({ userId, data }) => [
      `read("user:${userId}")`,
      `read("team:${wardTeam(data.state, data.lga, data.ward)}")`,
      'read("label:ewv")',
      'read("label:ewr")',
      'read("label:admin")',
    ],
  },

  verifications: {
    roles: VERIFIER,
    serverOwned: ['verifierId', 'verifierName', 'submittedAt',
                  'state', 'lga', 'ward'],
    create: ({ userId, profile }) => ({
      verifierId: userId,
      // Phase 1 denormalises the verifier's name onto the vote, because
      // Appwrite cannot join and the dispute list shows who voted. This
      // is what closes the gap the client adapter logs when it is asked
      // for a relation it cannot fetch.
      verifierName: profile.name ?? '',
      submittedAt: new Date().toISOString(),
    }),
    immutable: ['verifierId', 'reportId'],
    acl: ({ data }) => [
      `read("team:${wardTeam(data.state, data.lga, data.ward)}")`,
      'read("label:ewv")',
      'read("label:ewr")',
      'read("label:admin")',
    ],
  },

  verification_overrides: {
    roles: [...ADMIN, 'ewr'],
    serverOwned: ['decidedBy', 'decidedAt'],
    create: ({ userId }) => ({
      decidedBy: userId,
      decidedAt: new Date().toISOString(),
    }),
    immutable: ['decidedBy', 'reportId'],
    acl: () => ['read("label:ewr")', 'read("label:admin")'],
  },

  alerts: {
    roles: [...ADMIN, 'ewr', 'ldp_coordinator'],
    serverOwned: ['createdBy', 'createdAt'],
    create: ({ userId }) => ({
      createdBy: userId,
      createdAt: new Date().toISOString(),
    }),
    immutable: ['createdBy'],
    // Not `requiresLocation`: an alert has no ward, and the columns it
    // targets by are `targetState` / `targetLga`. Asking `assertLocation`
    // for `state`, `lga`, `ward` refused every alert ever created with
    // "Unknown state: undefined" — the rule was right, it was reading
    // fields the collection does not have.
    requiresTarget: true,
    acl: () => ['read("any")'],
  },

  // `requiresCoverage` replaces the Postgres CHECK constraint
  // `authorities_coverage_lga_needs_state`, which Appwrite has no equivalent
  // of; see `assertCoverage`.
  authorities: { roles: ADMIN, acl: () => ['read("any")'], requiresCoverage: true },
  knowledge_base: { roles: ADMIN, acl: () => ['read("any")'] },
  news_links: { roles: ADMIN, acl: () => ['read("any")'] },
  app_settings: { roles: ADMIN, acl: () => ['read("any")'] },

  profiles: {
    // The only self-service collection here, and the narrowest: role,
    // approval, ward and disabled status are the inputs to every other
    // rule in the system, so nobody edits their own.
    selfWritable: ['name', 'phone', 'address', 'avatarUrl', 'biometricsEnabled',
                   'notificationPreferences', 'preferredLanguage', 'lastLoginAt'],
    adminWritable: ['role', 'isApproved', 'isDisabled', 'state', 'lga', 'ward',
                    'isVerified'],
    acl: ({ documentId }) => [
      `read("user:${documentId}")`,
      'read("label:admin")',
      'read("label:techSupport")',
    ],
  },
};

/** Severities that make a report an alert, as `reports_before_insert` had it. */
export const ALERT_SEVERITIES = ['high', 'critical'];

/** Roles that may approve, reject or reopen a report. */
const DECIDERS = ['ewv', 'ewr', 'ldp_coordinator', 'project_staff', ...ADMIN];

const changed = (data, current, field) =>
  field in data && data[field] !== (current[field] ?? null);

/**
 * A report's own content, as `guard_report_update` listed it.
 *
 * The location fields are in here as well as in `immutable`: `immutable`
 * refuses them outright, and this list is what decides whether an edit
 * is a *content* edit at all.
 */
export const REPORT_CONTENT_FIELDS = [
  'state', 'lga', 'ward', 'latitude', 'longitude',
  'hazardType', 'severity', 'description', 'locationDetails', 'location',
  'address', 'imageUrls', 'submittedAt', 'type', 'reporterName',
  'createdAt', 'legacyFirebaseId', 'syncedAt',
];

/** Fields only an admin may move, per the Postgres guard. */
const OWNERSHIP_FIELDS = [
  'userId', 'escalated', 'escalationStatus', 'escalatedAt',
  'escalationReason', 'escalationScheduledAt',
];

/** Whether this patch edits the report itself rather than its decision. */
export const reportContentChanged = (current, data) =>
  REPORT_CONTENT_FIELDS.some((f) => changed(data, current, f));

/**
 * `guard_report_update()`, carried over.
 *
 * Four separate rules, and they are not the same rule:
 *
 *  - a report goes back to `pending` only through the reopen operation,
 *    which clears the votes and reschedules escalation; a bare status
 *    write would leave both behind;
 *  - the report's own content is the reporter's, only while it is still
 *    pending and only until somebody has voted on it;
 *  - ownership and escalation are an admin's to change;
 *  - the peer-verification tally is counted by confirmations, never set
 *    by hand, so only an admin may touch it or move a report to
 *    `verified` directly;
 *  - approving, rejecting and reopening need a reviewing role, and
 *    nobody but an admin may decide their own report.
 *
 * The one rule this cannot finish is "not after peers have voted",
 * which needs a read; `write.js` runs that one, gated on
 * [reportContentChanged], and this function is what says the rest.
 */
export function guardReportUpdate({ role, userId, current, data }) {
  const admin = isAdmin(role);

  // `raise exception 'Use reopen_report() ...'`. Without it a reviewer
  // can PATCH a decided report straight back to pending, which leaves
  // the old votes standing, the escalation unscheduled and the
  // superseded notifications still queued — the three things
  // `reopen_report` exists to do.
  if (data.status === 'pending' && (current.status ?? null) !== 'pending') {
    throw forbidden('Use the reopen operation to move a report back to pending');
  }

  if (reportContentChanged(current, data) && !admin) {
    if ((current.userId ?? null) !== userId) {
      throw forbidden("Only the reporter can edit a report's details");
    }
    // A staff reporter passes the role check on a report of any status,
    // so this is where "what was reviewed stays as it was" lives.
    if ((current.status ?? null) !== 'pending') {
      throw forbidden('A report can only be edited while it is pending');
    }
  }

  if (OWNERSHIP_FIELDS.some((f) => changed(data, current, f))) {
    if (!admin) throw forbidden('Only an admin can change report ownership or escalation');
  }

  const touchesTally =
    ['verificationCount', 'verifiedAt', 'autoValidated'].some((f) => changed(data, current, f)) ||
    (data.status === 'verified' && current.status !== 'verified');
  if (touchesTally && !admin) {
    throw forbidden('Reports are verified by peer confirmations');
  }

  const decides = ['status', 'approvedAt', 'rejectedAt', 'rejectionReason'].some((f) =>
    changed(data, current, f),
  );
  if (decides) {
    if (!DECIDERS.includes(role)) {
      throw forbidden('Your role cannot approve, reject or reopen reports');
    }
    if (!admin && current.userId === userId) {
      throw forbidden('You cannot approve or reject your own report');
    }
  }
}

export const isStaff = (role) => STAFF.includes(role) || ADMIN.includes(role);
export const isAdmin = (role) => ADMIN.includes(role);

/**
 * Validates a location against the bundled list.
 *
 * This is what replaces `alerts.target_lga_canonical → nigeria_lgas` and
 * `authorities.coverage_lga → nigeria_lgas`: Appwrite has no foreign keys,
 * and the same data already ships in the app. A ward the form offered and
 * the server rejects looks like a broken app, so the two lists are
 * generated from one source — see `tools/export_locations.dart`.
 */
export function assertLocation({ state, lga, ward }) {
  const lgas = locations[state];
  if (!lgas) throw invalid(`Unknown state: ${state}`, ErrorType.argument);
  const wards = lgas[lga];
  if (!wards) throw invalid(`Unknown LGA for ${state}: ${lga}`, ErrorType.argument);
  if (!wards.includes(ward)) {
    throw invalid(`Unknown ward for ${lga}: ${ward}`, ErrorType.argument);
  }
}

/**
 * Validates an alert's target: a state from the list, and either one of
 * its LGAs or every LGA.
 *
 * The same rule Postgres held as `alerts_target_lga_needs_state`: an LGA
 * without a state is not a thing an alert can be, because LGA names
 * repeat across states (Obi is in both Benue and Nasarawa), so one would
 * reach the wrong people or no one.
 */
export function assertTarget({ targetState, targetLga }) {
  const lga = (targetLga ?? '').trim();
  const state = (targetState ?? '').trim();
  const everywhere = lga === '' || lga.toLowerCase() === 'all';

  if (!state) {
    if (everywhere) return;
    throw invalid('An alert targeting an LGA must name its state', ErrorType.argument);
  }
  if (!locations[state]) {
    throw invalid(`Unknown state: ${state}`, ErrorType.argument);
  }
  if (everywhere) return;
  if (!locations[state][lga]) {
    throw invalid(`Unknown LGA for ${state}: ${lga}`, ErrorType.argument);
  }
}

/**
 * An SMS contact's coverage: an LGA, and the state that LGA belongs to.
 *
 * Six LGA names exist in two states — Obi is in both Benue and Nasarawa —
 * so a contact naming only the LGA would be texted about reports from the
 * wrong half of the country. Postgres refused that with the CHECK
 * constraint `authorities_coverage_lga_needs_state`; Appwrite has no CHECK
 * and `coverageState` is not a required column, so the rule lives here.
 */
export function assertCoverage({ coverageState, coverageLga }) {
  const lga = (coverageLga ?? '').trim();
  const state = (coverageState ?? '').trim();
  if (!lga) {
    throw invalid('An authority must cover an LGA', ErrorType.argument);
  }
  if (!state) {
    throw invalid('An authority covering an LGA must name its state', ErrorType.argument);
  }
  if (!locations[state]) {
    throw invalid(`Unknown state: ${state}`, ErrorType.argument);
  }
  if (!locations[state][lga]) {
    throw invalid(`Unknown LGA for ${state}: ${lga}`, ErrorType.argument);
  }
}

/**
 * Appwrite account labels for a profile row.
 *
 * Every `read("label:…")` ACL in `plan.mjs` and in `RULES` names a label,
 * and a label lives on the *account*, not on the profile row — so a
 * profile that says `role: 'admin'` grants nothing until the account
 * carries `admin`. Until this existed nothing in the running system ever
 * set one: only the one-off migration seeder did, so every role granted
 * after the migration read as a 200 with zero rows. Silent, and
 * indistinguishable from "there is no data".
 *
 * `ldp_coordinator` becomes `ldpCoordinator` because Appwrite labels are
 * alphanumeric. A disabled profile gets none: the account is blocked
 * anyway, and leaving a label on it would outlive the block if it were
 * ever lifted by hand.
 *
 * **The role label requires approval**, which is what `app_role()` does:
 *
 *     case when p.is_approved and not p.is_disabled then p.role else 'user' end
 *
 * Every RLS policy branched on that, never on the column, so an unapproved
 * staff account was a plain user to Postgres. This used to hand out the label
 * from `role` alone, and since no ACL anywhere names `label:approved` as well
 * as the role, such an account arrived holding the full reach of its role —
 * every profile, every report, every verification — the moment any profile
 * field was touched. `syncLabels` re-runs this whenever `role`, `isApproved`
 * or `isDisabled` changes, so approving an account grants the label then.
 */
export function accountLabels({ role, isApproved, isDisabled }) {
  if (isDisabled === true) return [];
  const labels = [];
  const approved = isApproved === true;
  const name = String(role ?? '').replace(/_(.)/g, (_, c) => c.toUpperCase());
  if (approved && name && name !== 'user' && LABELS.includes(name)) labels.push(name);
  if (approved) labels.push('approved');
  return labels;
}

/** Every label an ACL may name; anything else is not a label Appwrite knows. */
const LABELS = [
  'ewm', 'ewv', 'ewr', 'ldpCoordinator', 'projectStaff', 'admin',
  'techSupport', 'approved',
];

/** The profile fields whose value decides the account's labels. */
export const LABEL_FIELDS = ['role', 'isApproved', 'isDisabled'];

/** Refuses when [role] is not in [allowed]. */
export function assertRole(role, allowed, what) {
  if (!allowed || allowed.includes(role)) return;
  throw forbidden(`Your role does not allow you to ${what}`);
}
