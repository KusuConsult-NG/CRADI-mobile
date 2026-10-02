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
    requiresLocation: true,
    acl: () => ['read("any")'],
  },

  authorities: { roles: ADMIN, acl: () => ['read("any")'] },
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

/** Refuses when [role] is not in [allowed]. */
export function assertRole(role, allowed, what) {
  if (!allowed || allowed.includes(role)) return;
  throw forbidden(`Your role does not allow you to ${what}`);
}
