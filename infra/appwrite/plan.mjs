/**
 * The target state of the Appwrite project, declared.
 *
 * `provision.mjs` makes a project match this and `verify.mjs` reports
 * where it does not. Everything traces to a phase of the migration doc:
 * the collection list and write rules to Phase 1, the ACLs to Phase 0,
 * buckets and topics to Phase 3, Functions to Phases 10 and 11.
 */
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const columns = JSON.parse(readFileSync(resolve(here, 'columns.json'), 'utf8'));

/**
 * The project the migration targets.
 *
 * Frankfurt, which is both where the previous Appwrite project lived and
 * the region chosen for this one. Recording the choice here rather than
 * only in a shell history, because moving an Appwrite Cloud project
 * between regions means migrating everything a second time.
 */
export const ENDPOINT =
  process.env.APPWRITE_ENDPOINT ?? 'https://fra.cloud.appwrite.io/v1';

export const DATABASE_ID = process.env.APPWRITE_DATABASE_ID ?? 'cradi';
export const DATABASE_NAME = 'CRADI';

/**
 * Columns Phase 1 adds that no Postgres table has.
 *
 * Appwrite cannot join, so the few fields the app reads across a
 * relationship are denormalised onto the document at write time. Each is
 * set by the `write` Function and listed in its `serverOwned`, so a
 * client cannot supply one.
 */
const DENORMALISED = {
  reports: [
    { key: 'userName', type: 'string', size: 8192, required: false },
    { key: 'userRole', type: 'string', size: 64, required: false },
    // What the status was before this write. Appwrite's event payload is
    // the document with no "before", so the event Function cannot
    // otherwise tell a status change from any other edit (Phase 11).
    { key: 'previousStatus', type: 'string', size: 32, required: false },
  ],
  verifications: [
    { key: 'verifierName', type: 'string', size: 8192, required: false },
    // The verification write Function needs these to enforce the EWM
    // rule and already reads the report, so they are copied over and the
    // read path never needs the join.
    { key: 'state', type: 'string', size: 128, required: false },
    { key: 'lga', type: 'string', size: 128, required: false },
    { key: 'ward', type: 'string', size: 128, required: false },
  ],
  reports_reopen: [],
};

/** Columns the worker needs that the Postgres outbox named differently. */
const WORKER_OVERRIDES = {
  notification_outbox: [
    { key: 'eventType', type: 'string', size: 64, required: true },
    { key: 'payload', type: 'string', size: 65535, required: false },
    { key: 'attempts', type: 'integer', required: false },
    { key: 'availableAt', type: 'datetime', required: false },
    { key: 'processedAt', type: 'datetime', required: false },
    // `last_error` in Postgres. Renamed because the drain also writes a
    // success note here ("report no longer pending"), and calling that
    // an error made every quiet skip look like a failure.
    { key: 'note', type: 'string', size: 8192, required: false },
  ],
};

const cols = (table, extra = []) => [
  ...(WORKER_OVERRIDES[table] ?? columns[table] ?? []),
  ...extra,
];

/**
 * The 19 collections.
 *
 * `clientWrite` must agree with `AppwriteConfig.clientWritableCollections`
 * in the app; `functions/cradi/test/policy.test.mjs` fails if they drift.
 */
export const COLLECTIONS = [
  {
    id: 'profiles',
    name: 'Profiles',
    columns: cols('profiles'),
    indexes: [
      { key: 'by_role_lga_ward', type: 'key', attributes: ['role', 'lga', 'ward'] },
      { key: 'by_role', type: 'key', attributes: ['role'] },
    ],
    // Documents carry their own ACL; the collection grants nothing.
    permissions: [],
    documentSecurity: true,
  },
  {
    id: 'reports',
    name: 'Reports',
    columns: cols('reports', DENORMALISED.reports),
    indexes: [
      { key: 'by_status_created', type: 'key', attributes: ['status', '$createdAt'] },
      { key: 'by_user', type: 'key', attributes: ['userId'] },
      { key: 'by_ward', type: 'key', attributes: ['state', 'lga', 'ward'] },
    ],
    permissions: [],
    documentSecurity: true,
  },
  {
    id: 'verifications',
    name: 'Verifications',
    columns: cols('verifications', DENORMALISED.verifications),
    indexes: [
      { key: 'by_report', type: 'key', attributes: ['reportId'] },
      { key: 'by_verifier', type: 'key', attributes: ['verifierId'] },
    ],
    permissions: [],
    documentSecurity: true,
  },
  {
    id: 'verification_overrides',
    name: 'Verification overrides',
    columns: cols('verification_overrides'),
    indexes: [{ key: 'by_report', type: 'key', attributes: ['reportId'] }],
    permissions: ['read("label:ewr")', 'read("label:admin")'],
  },
  {
    id: 'alerts',
    name: 'Alerts',
    columns: cols('alerts'),
    indexes: [
      { key: 'by_active_created', type: 'key', attributes: ['isActive', '$createdAt'] },
      { key: 'by_target', type: 'key', attributes: ['targetState', 'targetLga'] },
    ],
    permissions: ['read("any")'],
  },
  {
    id: 'authorities',
    name: 'Authorities',
    columns: cols('authorities'),
    indexes: [{ key: 'by_coverage', type: 'key', attributes: ['coverageState', 'coverageLga'] }],
    permissions: ['read("label:admin")'],
  },
  {
    id: 'contacts',
    name: 'Emergency contacts',
    columns: cols('contacts'),
    indexes: [{ key: 'by_user', type: 'key', attributes: ['userId'] }],
    permissions: ['create("users")'],
    documentSecurity: true,
    clientWrite: true,
  },
  {
    id: 'messages',
    name: 'Chat messages',
    columns: cols('messages'),
    indexes: [{ key: 'by_chat_sent', type: 'key', attributes: ['chatId', 'sentAt'] }],
    permissions: ['create("users")', 'read("label:approved")'],
    documentSecurity: true,
    clientWrite: true,
  },
  {
    id: 'trusted_devices',
    name: 'Trusted devices',
    columns: cols('trusted_devices'),
    indexes: [{ key: 'by_user', type: 'key', attributes: ['userId'] }],
    permissions: ['create("users")'],
    documentSecurity: true,
    clientWrite: true,
  },
  {
    id: 'login_history',
    name: 'Login history',
    // Append-only: it records failures too, which is the half an Appwrite
    // session list cannot replace (Phase 2).
    columns: cols('login_history'),
    indexes: [{ key: 'by_user_time', type: 'key', attributes: ['userId', 'occurredAt'] }],
    permissions: ['create("users")'],
    documentSecurity: true,
    clientWrite: true,
  },
  {
    id: 'ndpa_consents',
    name: 'NDPA consents',
    columns: cols('ndpa_consents'),
    indexes: [],
    permissions: ['create("users")'],
    documentSecurity: true,
    clientWrite: true,
  },
  {
    id: 'knowledge_base',
    name: 'Knowledge base',
    columns: cols('knowledge_base'),
    indexes: [{ key: 'by_category', type: 'key', attributes: ['category'] }],
    permissions: ['read("any")'],
  },
  {
    id: 'news_links',
    name: 'News links',
    columns: cols('news_links'),
    indexes: [{ key: 'by_active_order', type: 'key', attributes: ['isActive', 'sortOrder'] }],
    permissions: ['read("any")'],
  },
  {
    id: 'app_settings',
    name: 'App settings',
    columns: cols('app_settings'),
    indexes: [],
    permissions: ['read("any")'],
  },
  {
    id: 'scheduled_escalations',
    name: 'Scheduled escalations',
    columns: cols('scheduled_escalations'),
    indexes: [{ key: 'by_status_due', type: 'key', attributes: ['status', 'escalateAt'] }],
    // Server only: nothing reads these but the cron.
    permissions: [],
  },
  {
    id: 'notification_outbox',
    name: 'Notification outbox',
    columns: cols('notification_outbox'),
    indexes: [
      { key: 'by_due', type: 'key', attributes: ['processedAt', 'availableAt', 'attempts'] },
    ],
    permissions: [],
  },
  {
    id: 'sms_deliveries',
    name: 'SMS deliveries',
    columns: cols('sms_deliveries'),
    indexes: [
      { key: 'by_report', type: 'key', attributes: ['reportId'] },
      // The daily cap counts from here, keyed by (state, lga) because
      // LGA names repeat across states.
      { key: 'by_area_day', type: 'key', attributes: ['lga', 'state', '$createdAt'] },
    ],
    permissions: [],
  },
  {
    id: 'alerts_unresolved_target',
    name: 'Alerts — unresolved target',
    columns: cols('alerts_unresolved_target'),
    indexes: [],
    // Quarantine: RLS on with no policy today, so service-role only.
    permissions: [],
  },
  {
    id: 'authorities_unresolved_coverage',
    name: 'Authorities — unresolved coverage',
    columns: cols('authorities_unresolved_coverage'),
    indexes: [],
    permissions: [],
  },
];

/**
 * Phase 3. Evidence is immutable: a bucket whose files are created and
 * never updated, with the ACL on each file.
 */
export const SINGLE_BUCKET_ID = 'cradi-files';

/**
 * One bucket instead of two, for a project whose tier allows only one.
 *
 * The previous Appwrite project ran this way — its config says so: *"Due
 * to Appwrite free tier limits (max 1 bucket), Profile Photos and Report
 * Images currently share the same bucket"*.
 *
 * It is not a security compromise **provided `fileSecurity` stays on**.
 * With per-file ACLs, evidence still carries its ward-team reads and a
 * profile image still carries `read("any")`; what is shared is the size
 * cap, the extension list and the antivirus setting, and those are the
 * same for both anyway. A file written with no permissions falls back to
 * the bucket's, which grant no reads — so the failure mode is a file
 * nobody can see, not a file everybody can.
 *
 * What it does cost: the two cannot be given different retention or
 * deleted independently, and a bug in the evidence path can now write
 * into the same bucket as avatars.
 */
export const SINGLE_BUCKET = {
  id: SINGLE_BUCKET_ID,
  name: 'CRADI files',
  permissions: ['create("users")'],
  fileSecurity: true,
  maximumFileSize: 10 * 1024 * 1024,
  allowedFileExtensions: ['jpg', 'jpeg', 'png', 'webp'],
  compression: 'none',
  encryption: true,
  antivirus: true,
};

export const BUCKETS = [
  {
    id: 'report-images',
    name: 'Report evidence',
    // `read("any")`, deliberately, and it is not a loosening: the app
    // renders evidence with `CachedNetworkImage`, which sends no
    // credential, and today's Supabase bucket is already public — every
    // stored URL is a `/storage/v1/object/public/` one. Anything
    // narrower makes the photos unrenderable rather than private.
    //
    // What protects them is that the URL is unguessable: the file id is
    // a digest of a path containing the report's uuid (see
    // `AppwriteDataBackend.fileIdFor`). Tightening this means giving the
    // image loader an auth header first; until then `fileSecurity: true`
    // with no read rule just produced a 404 for everyone, uploader
    // included.
    permissions: ['create("users")', 'read("any")'],
    fileSecurity: false,
    maximumFileSize: 10 * 1024 * 1024,
    allowedFileExtensions: ['jpg', 'jpeg', 'png', 'webp'],
    compression: 'none', // the client already compresses before upload
    encryption: true,
    antivirus: true,
  },
  {
    id: 'profile-images',
    name: 'Profile images',
    // Readable by anyone, for the same reason as the evidence bucket:
    // the image loader sends no credential. `fileSecurity` is on so the
    // per-file rules the uploader gets (see `AppwriteDataBackend._put`)
    // can add `update`/`delete` for that one owner — an avatar is
    // replaced, unlike evidence. Granting `delete("users")` on the
    // bucket instead would let any signed-in user delete anyone's.
    permissions: ['create("users")', 'read("any")'],
    fileSecurity: true,
    maximumFileSize: 5 * 1024 * 1024,
    allowedFileExtensions: ['jpg', 'jpeg', 'png', 'webp'],
    compression: 'none',
    encryption: true,
    antivirus: true,
  },
];

/**
 * The open-runtimes contract version.
 *
 * Appwrite 1.8 defaults a new Function to `v5`, and executor 0.7.22 —
 * which is the version 1.8's own compose template pins — rejects it:
 * *"Invalid `version` param: Value must be one of (v2, v4)"*. The
 * mismatch is between two components of the same release, and it
 * surfaces only at build time, as seven identical failures with no
 * mention of the word "function".
 */
export const FUNCTION_VERSION = process.env.APPWRITE_FUNCTION_VERSION ?? 'v4';

/** Phases 10 and 11. */
export const FUNCTIONS = [
  {
    id: 'write', name: 'Write', entrypoint: 'src/write.js', execute: ['users'],
    // `users.write` so a profile's role, approval and disabled flag stay
    // in step with the account's labels — every `read("label:…")` ACL
    // below is granted by a label on the account, not by the row.
    scopes: [
      'databases.read', 'documents.read', 'documents.write',
      'teams.read', 'teams.write', 'users.read', 'users.write',
    ],
  },
  {
    id: 'auth', name: 'Auth', entrypoint: 'src/auth.js', execute: ['any'],
    // `any`: registration and recovery happen before there is a session.
    scopes: ['users.read', 'users.write', 'sessions.write', 'documents.write', 'messages.write'],
  },
  {
    id: 'operation', name: 'Operations', entrypoint: 'src/operation.js', execute: ['users'],
    scopes: ['documents.read', 'documents.write'],
  },
  {
    id: 'on-write', name: 'On write', entrypoint: 'src/on-write.js', execute: [],
    scopes: ['documents.write'],
    // `databases.`, not `tablesdb.`. The two namespaces differ and the
    // difference is not guessable: Realtime channels are
    // `tablesdb.<db>.tables.<t>.rows`, which is what the Flutter SDK's
    // channel builder produces, while Function *events* are rooted at
    // `databases` — `app/config/events.php` in the server image is the
    // only place that says so. A wrong event name is a 400 at
    // provisioning time, which is the good failure; silently subscribing
    // to nothing would have been the bad one.
    events: [
      `databases.${DATABASE_ID}.tables.reports.rows.*.create`,
      `databases.${DATABASE_ID}.tables.reports.rows.*.update`,
      `databases.${DATABASE_ID}.tables.verifications.rows.*.create`,
      `databases.${DATABASE_ID}.tables.alerts.rows.*.create`,
      `databases.${DATABASE_ID}.tables.profiles.rows.*.update`,
    ],
  },
  {
    id: 'drain', name: 'Outbox drain', entrypoint: 'src/drain.js', execute: [],
    scopes: ['documents.read', 'documents.write', 'users.write', 'messages.write', 'targets.read'],
    schedule: '* * * * *',
  },
  {
    id: 'escalate', name: 'Escalation cron', entrypoint: 'src/escalate.js', execute: [],
    scopes: ['documents.read', 'documents.write', 'messages.write', 'targets.read'],
    schedule: '* * * * *',
  },
  {
    id: 'reconcile', name: 'Reconciling sweep', entrypoint: 'src/reconcile.js', execute: [],
    scopes: ['documents.read', 'documents.write'],
    schedule: '*/5 * * * *',
  },
];

/** The labels Phase 1 uses in ACLs. Appwrite labels are alphanumeric only. */
export const LABELS = [
  'ewm', 'ewv', 'ewr', 'ldpCoordinator', 'projectStaff', 'admin',
  'techSupport', 'approved',
];

export const clientWritable = () =>
  COLLECTIONS.filter((c) => c.clientWrite).map((c) => c.id);
