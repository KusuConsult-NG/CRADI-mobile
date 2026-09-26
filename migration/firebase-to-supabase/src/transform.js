// Pure transformation helpers: Firestore document (camelCase) → Supabase row
// (snake_case). Nothing in this module performs I/O, so it is unit-tested in
// test/transform.test.js.
//
// Row transformers return { row, skip, warnings }:
//   row       the row to write (undefined when skipped)
//   skip      a reason string when the document cannot be imported
//   warnings  non-fatal issues (unresolved optional references, defaults used)
//
// They take a `ctx` object of resolvers so they stay pure:
//   ctx.user(firebaseUid)     → supabase profile uuid | null
//   ctx.report(firestoreId)   → supabase report uuid | null
//   ctx.url(firebaseUrl)      → rewritten URL (identity when storage is skipped)
//   ctx.now                   → ISO timestamp used as a last-resort default

import { randomUUID } from 'node:crypto';

// ── Scalars ──────────────────────────────────────────────────────────────────

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function isUuid(value) {
  return typeof value === 'string' && UUID_RE.test(value);
}

/**
 * Coerce a Firestore Timestamp, a serialized Timestamp ({_seconds} or
 * {seconds}), a Date, an ISO string, or epoch millis/seconds into an ISO
 * string. Returns null for missing or unparseable values.
 */
export function toIso(value) {
  if (value === null || value === undefined || value === '') return null;
  let date = null;
  if (value instanceof Date) {
    date = value;
  } else if (typeof value === 'object') {
    if (typeof value.toDate === 'function') {
      date = value.toDate();
    } else if (typeof value._seconds === 'number' || typeof value.seconds === 'number') {
      const seconds = value._seconds ?? value.seconds;
      const nanos = value._nanoseconds ?? value.nanoseconds ?? 0;
      date = new Date(seconds * 1000 + Math.floor(nanos / 1e6));
    }
  } else if (typeof value === 'number') {
    // Heuristic: values below 1e12 are epoch seconds, otherwise millis.
    date = new Date(value < 1e12 ? value * 1000 : value);
  } else if (typeof value === 'string') {
    const trimmed = value.trim();
    if (/^\d+$/.test(trimmed)) return toIso(Number(trimmed));
    date = new Date(trimmed);
  }
  if (!date || Number.isNaN(date.getTime())) return null;
  return date.toISOString();
}

export function asText(value, fallback = '') {
  if (value === null || value === undefined) return fallback;
  if (typeof value === 'string') return value.trim();
  if (typeof value === 'number' || typeof value === 'boolean') return String(value);
  return fallback;
}

export function asNullableText(value) {
  const text = asText(value, '');
  return text === '' ? null : text;
}

// Older app builds HTML-escaped user text before storing it (InputSanitizer
// .sanitize: & < > " ' / → entities), so e.g. "don't" was saved as
// "don&#x27;t". Free text is stored raw in Supabase; decode exactly those
// entities once (single pass, so "&amp;lt;" becomes the literal "&lt;").
const HTML_ENTITIES = {
  '&amp;': '&',
  '&lt;': '<',
  '&gt;': '>',
  '&quot;': '"',
  '&#x27;': "'",
  '&#39;': "'",
  '&#039;': "'",
  '&apos;': "'",
  '&#x2f;': '/',
  '&#47;': '/',
};
const HTML_ENTITY_RE = /&(?:amp|lt|gt|quot|apos|#x27|#0?39|#x2f|#47);/gi;

export function decodeHtmlEntities(text) {
  if (typeof text !== 'string' || !text.includes('&')) return text;
  return text.replace(HTML_ENTITY_RE, (m) => HTML_ENTITIES[m.toLowerCase()] ?? m);
}

/** asText for user-entered free text: also undoes legacy HTML escaping. */
export function asFreeText(value, fallback = '') {
  return decodeHtmlEntities(asText(value, fallback));
}

export function asNullableFreeText(value) {
  const text = asFreeText(value, '');
  return text === '' ? null : text;
}

export function asBool(value, fallback = false) {
  if (typeof value === 'boolean') return value;
  if (value === 'true' || value === 1 || value === '1') return true;
  if (value === 'false' || value === 0 || value === '0') return false;
  return fallback;
}

export function asNumber(value) {
  if (value === null || value === undefined || value === '') return null;
  const n = typeof value === 'number' ? value : Number(value);
  return Number.isFinite(n) ? n : null;
}

export function asInt(value, fallback = 0) {
  const n = asNumber(value);
  return n === null ? fallback : Math.trunc(n);
}

/** A Firestore reference field may hold a string id, a DocumentReference or a path. */
export function refId(value) {
  if (value === null || value === undefined) return null;
  if (typeof value === 'string') {
    const trimmed = value.trim();
    if (!trimmed) return null;
    const parts = trimmed.split('/');
    return parts[parts.length - 1];
  }
  if (typeof value === 'object' && typeof value.id === 'string') return value.id;
  return null;
}

// ── Enumerations ─────────────────────────────────────────────────────────────

export const REPORT_STATUSES = ['pending', 'verified', 'approved', 'rejected'];

const LEGACY_STATUS = {
  acknowledged: 'verified',
  validated: 'approved',
  resolved: 'approved',
};

/**
 * Normalise a report status. Returns { status, escalated, known }.
 * `escalated` is true when the legacy status was 'escalated' (→ pending) or
 * the document already carried escalated=true.
 */
export function normalizeReportStatus(raw, escalatedFlag = false) {
  const value = asText(raw).toLowerCase();
  const escalated = asBool(escalatedFlag, false);
  if (REPORT_STATUSES.includes(value)) return { status: value, escalated, known: true };
  if (value in LEGACY_STATUS) return { status: LEGACY_STATUS[value], escalated, known: true };
  if (value === 'escalated') return { status: 'pending', escalated: true, known: true };
  return { status: 'pending', escalated, known: value === '' };
}

export const SEVERITIES = ['low', 'medium', 'high', 'critical'];

/**
 * Mirror of the app's normalizeSeverity(): 'High Severity', 'HIGH', 'moderate',
 * 'severe', 'extreme'. Returns null for missing / unrecognised values.
 */
export function normalizeSeverity(raw) {
  if (raw === null || raw === undefined) return null;
  const value = String(raw).trim().toLowerCase().replace(/\s*severity$/, '').trim();
  if (SEVERITIES.includes(value)) return value;
  if (value === 'moderate') return 'medium';
  if (value === 'severe' || value === 'extreme') return 'critical';
  return null;
}

export const ALERT_SEVERITIES = ['info', 'warning', 'critical'];

export function normalizeAlertSeverity(raw) {
  const value = asText(raw).toLowerCase();
  if (ALERT_SEVERITIES.includes(value)) return value;
  const report = normalizeSeverity(value);
  if (report === 'critical') return 'critical';
  if (report === 'high' || report === 'medium' || value === 'warn') return 'warning';
  if (report === 'low') return 'info';
  return null;
}

export const ROLES = [
  'user', 'ewm', 'ewv', 'ewr', 'ldp_coordinator', 'project_staff', 'admin', 'techSupport',
];

/** Case/format-insensitive role match (e.g. 'EWM', 'tech_support', 'LDP Coordinator'). */
export function normalizeRole(raw) {
  const key = asText(raw).toLowerCase().replace(/[\s_-]/g, '');
  if (!key) return null;
  for (const role of ROLES) {
    if (role.toLowerCase().replace(/_/g, '') === key) return role;
  }
  if (key === 'ldpcoordinator' || key === 'coordinator') return 'ldp_coordinator';
  if (key === 'staff' || key === 'projectstaff') return 'project_staff';
  if (key === 'support' || key === 'techsupport') return 'techSupport';
  return null;
}

export function normalizeOverrideAction(raw) {
  const value = asText(raw).toLowerCase();
  if (['approved', 'approve', 'validated', 'validate', 'resolved'].includes(value)) return 'approved';
  if (['rejected', 'reject', 'declined', 'decline'].includes(value)) return 'rejected';
  return null;
}

// ── Phone accounts ───────────────────────────────────────────────────────────

const PHONE_EMAIL_RE = /^\+?(\d{6,15})@ewer\.phone$/i;

export function isPhoneEmail(email) {
  return typeof email === 'string' && PHONE_EMAIL_RE.test(email.trim());
}

/** '2348012345678@ewer.phone' → '+2348012345678'; null for any other value. */
export function phoneFromFakeEmail(email) {
  if (typeof email !== 'string') return null;
  const match = email.trim().match(PHONE_EMAIL_RE);
  return match ? `+${match[1]}` : null;
}

/** Normalise a phone number to '+<digits>' (E.164-ish), or null. */
export function toE164(raw) {
  const text = asText(raw);
  if (!text) return null;
  let digits = text.replace(/[^\d]/g, '');
  if (!digits) return null;
  // Local Nigerian format 080xxxxxxxx → +23480xxxxxxxx
  if (!text.startsWith('+') && digits.length === 11 && digits.startsWith('0')) {
    digits = `234${digits.slice(1)}`;
  }
  return digits.length >= 6 && digits.length <= 15 ? `+${digits}` : null;
}

// ── Storage URLs ─────────────────────────────────────────────────────────────

/**
 * Extract { bucket, path } (path decoded) from a Firebase Storage reference:
 *   https://firebasestorage.googleapis.com/v0/b/<bucket>/o/<encoded path>?alt=media&token=…
 *   https://storage.googleapis.com/<bucket>/<path>
 *   https://<bucket>.storage.googleapis.com/<path>
 *   gs://<bucket>/<path>
 * Returns null for anything else (local file paths, Supabase URLs, junk).
 */
export function extractStoragePath(url) {
  if (typeof url !== 'string' || !url.trim()) return null;
  const raw = url.trim();
  if (raw.startsWith('gs://')) {
    const rest = raw.slice(5);
    const slash = rest.indexOf('/');
    if (slash <= 0) return null;
    return { bucket: rest.slice(0, slash), path: safeDecode(rest.slice(slash + 1)) };
  }
  let parsed;
  try {
    parsed = new URL(raw);
  } catch {
    return null;
  }
  const host = parsed.hostname;
  if (host === 'firebasestorage.googleapis.com') {
    const match = parsed.pathname.match(/^\/v0\/b\/([^/]+)\/o\/(.+)$/);
    if (!match) return null;
    return { bucket: safeDecode(match[1]), path: safeDecode(match[2]) };
  }
  if (host === 'storage.googleapis.com') {
    const match = parsed.pathname.match(/^\/([^/]+)\/(.+)$/);
    if (!match) return null;
    return { bucket: match[1], path: safeDecode(match[2]) };
  }
  if (host.endsWith('.storage.googleapis.com')) {
    return {
      bucket: host.slice(0, -'.storage.googleapis.com'.length),
      path: safeDecode(parsed.pathname.replace(/^\//, '')),
    };
  }
  return null;
}

function safeDecode(s) {
  try {
    return decodeURIComponent(s);
  } catch {
    return s;
  }
}

const STORAGE_PREFIXES = {
  report_images: 'report-images',
  profile_images: 'profile-images',
};

export const FIREBASE_STORAGE_PREFIXES = Object.keys(STORAGE_PREFIXES);

/**
 * Map a Firebase object path to its Supabase destination.
 *   report_images/<uid>/<rest>  → { bucket: 'report-images',  path: '<newUserId>/<rest>', uid }
 *   profile_images/<uid>/<rest> → { bucket: 'profile-images', path: '<newUserId>/<rest>', uid }
 * `resolveUser(uid)` maps the Firebase uid to the Supabase user id.
 * Returns null when the path is outside those prefixes or the user is unknown.
 */
export function storageTargetFor(objectPath, resolveUser) {
  if (typeof objectPath !== 'string') return null;
  const parts = objectPath.split('/').filter(Boolean);
  if (parts.length < 3) return null;
  const bucket = STORAGE_PREFIXES[parts[0]];
  if (!bucket) return null;
  const uid = parts[1];
  const newUserId = resolveUser(uid);
  if (!newUserId) return null;
  return { bucket, path: `${newUserId}/${parts.slice(2).join('/')}`, uid };
}

/** Rewrite a Firebase URL using a map of decoded object path → new URL. */
export function rewriteUrl(url, urlMap) {
  const ref = extractStoragePath(url);
  if (!ref) return url;
  const mapped = urlMap instanceof Map ? urlMap.get(ref.path) : urlMap?.[ref.path];
  return mapped ?? url;
}

/** Only keep http(s) image URLs; the app occasionally stored local file paths. */
export function cleanImageUrl(value) {
  const text = asText(value);
  return /^https?:\/\//i.test(text) ? text : '';
}

// ── Row transformers ─────────────────────────────────────────────────────────

function result(row, warnings = []) {
  return { row, skip: null, warnings };
}

function skipped(reason, warnings = []) {
  return { row: undefined, skip: reason, warnings };
}

/**
 * Combine a Firebase Auth record (may be null) and a Firestore users doc (may
 * be null) into { auth, profile }:
 *   auth    parameters for supabase.auth.admin.createUser (minus password)
 *   profile columns to write onto the auto-created profiles row
 *   kind    'email' | 'phone'
 */
export function transformUser(uid, authRecord, doc, ctx) {
  const d = doc ?? {};
  const a = authRecord ?? {};
  const warnings = [];

  const authEmail = asText(a.email) || asText(d.email);
  const fakePhone = phoneFromFakeEmail(authEmail);
  // Firebase phone-auth users (no email) carry phoneNumber instead.
  const phone = fakePhone ?? (authEmail ? null : toE164(a.phoneNumber));
  const kind = fakePhone || (!authEmail && phone) ? 'phone' : authEmail ? 'email' : null;
  if (!kind) return skipped('no email or phone on auth record or user document');

  const role = normalizeRole(d.role);
  if (d.role !== undefined && !role) warnings.push(`unknown role '${d.role}' → user`);
  const verified = asBool(a.emailVerified, false) || asBool(d.isVerified, false);
  const profilePhone = asText(d.phone) || phone || asText(a.phoneNumber) || '';

  const metadata = {
    name: asFreeText(d.name) || asFreeText(a.displayName) || 'User',
    role: role ?? 'user',
    state: asText(d.state),
    lga: asText(d.lga),
    ward: asText(d.ward),
    phone: profilePhone,
    address: asFreeText(d.address),
  };

  // An account an admin already approved in Firebase keeps its approval; the
  // database only accepts approval of confirmed accounts, so it is imported
  // as confirmed (the admin vouched for it before the migration).
  const approved = asBool(d.isApproved, false);
  if (approved && !verified && kind !== 'phone') {
    warnings.push('approved in Firebase but email not verified; imported as confirmed');
  }
  const auth = kind === 'phone'
    ? { phone, phone_confirm: true, user_metadata: metadata }
    : { email: authEmail.toLowerCase(), email_confirm: verified || approved, user_metadata: metadata };

  const created = toIso(d.createdAt) ?? toIso(a.metadata?.creationTime);
  const profile = {
    name: metadata.name,
    role: metadata.role,
    state: metadata.state,
    lga: metadata.lga,
    ward: metadata.ward,
    phone: metadata.phone,
    address: metadata.address,
    is_approved: approved,
    is_disabled: asBool(d.isDisabled, false) || asBool(a.disabled, false),
    is_verified: verified || kind === 'phone',
    biometrics_enabled: asBool(d.biometricsEnabled, false),
    monitoring_zone: asText(d.monitoringZone),
    profile_image_url: ctx.url(cleanImageUrl(d.profileImageUrl || a.photoURL)),
    registration_code: asNullableText(d.registrationCode),
    last_login_at: toIso(d.lastLoginAt) ?? toIso(a.metadata?.lastSignInTime),
    legacy_firebase_uid: uid,
  };
  if (created) profile.created_at = created;
  if (!doc) warnings.push('no Firestore users document; profile uses defaults');
  if (!authRecord) warnings.push('no Firebase Auth record; created from Firestore document only');
  return { ...result({ auth, profile }, warnings), kind };
}

export function transformReport(id, d, ctx) {
  const warnings = [];
  const userUid = refId(d.userId ?? d.reporterId);
  const userId = userUid ? ctx.user(userUid) : null;
  if (userUid && !userId) warnings.push(`reporter ${userUid} not migrated; user_id set to null`);

  const { status, escalated, known } = normalizeReportStatus(d.status, d.escalated);
  if (!known) warnings.push(`unknown status '${d.status}' → pending`);
  let severity = normalizeSeverity(d.severity);
  if (!severity) {
    warnings.push(`unknown severity '${d.severity}' → medium`);
    severity = 'medium';
  }
  let lga = asText(d.lga);
  if (!lga) {
    warnings.push('missing lga → Unknown');
    lga = 'Unknown';
  }
  const submitted = toIso(d.submittedAt) ?? toIso(d.createdAt) ?? toIso(d.timestamp);
  if (!submitted) warnings.push('missing submittedAt; using import time');

  // `location` is normally a string, but tolerate a GeoPoint.
  const geo = d.location && typeof d.location === 'object' ? d.location : null;
  const locationText = geo ? '' : asFreeText(d.location);
  const images = Array.isArray(d.imageUrls) ? d.imageUrls : d.imageUrl ? [d.imageUrl] : [];

  const updatedByUid = refId(d.updatedBy);
  return result({
    user_id: userId,
    reporter_name: asNullableFreeText(d.reporterName),
    hazard_type: asText(d.hazardType) || asText(d.type) || 'unknown',
    severity,
    latitude: asNumber(d.latitude) ?? asNumber(geo?.latitude ?? geo?._latitude),
    longitude: asNumber(d.longitude) ?? asNumber(geo?.longitude ?? geo?._longitude),
    location_details: asFreeText(d.locationDetails) || locationText,
    location: locationText || asFreeText(d.locationDetails),
    address: asFreeText(d.address),
    ward: asText(d.ward),
    lga,
    state: asText(d.state),
    description: asFreeText(d.description),
    submitted_at: submitted ?? ctx.now,
    image_urls: images.map(cleanImageUrl).filter(Boolean).map(ctx.url),
    status,
    type: asNullableText(d.type),
    is_alert: severity === 'high' || severity === 'critical',
    verification_count: Math.max(0, asInt(d.verificationCount, 0)),
    verified_at: toIso(d.verifiedAt),
    auto_validated: asBool(d.autoValidated, false),
    approved_at: toIso(d.approvedAt),
    rejected_at: toIso(d.rejectedAt),
    rejection_reason: asNullableFreeText(d.rejectionReason),
    escalated,
    escalated_at: toIso(d.escalatedAt),
    escalation_reason: asNullableText(d.escalationReason),
    escalation_scheduled_at: toIso(d.escalationScheduledAt),
    escalation_status: asNullableText(d.escalationStatus),
    updated_by: updatedByUid ? ctx.user(updatedByUid) : null,
    synced_at: toIso(d.syncedAt),
    legacy_firebase_id: id,
    created_at: toIso(d.createdAt) ?? submitted ?? ctx.now,
  }, warnings);
}

export function transformVerification(id, d, ctx) {
  const reportFb = refId(d.reportId);
  const reportId = reportFb ? ctx.report(reportFb) : null;
  if (!reportId) return skipped(`report ${reportFb ?? '(missing)'} not migrated`);
  const verifierFb = refId(d.verifierId ?? d.userId);
  const verifierId = verifierFb ? ctx.user(verifierFb) : null;
  if (!verifierId) return skipped(`verifier ${verifierFb ?? '(missing)'} not migrated`);
  const submitted = toIso(d.submittedAt) ?? toIso(d.createdAt) ?? toIso(d.timestamp) ?? ctx.now;
  return result({
    report_id: reportId,
    verifier_id: verifierId,
    is_confirmed: asBool(d.isConfirmed, false),
    comment: asFreeText(d.comment),
    submitted_at: submitted,
    created_at: toIso(d.createdAt) ?? submitted,
  });
}

export function transformVerificationOverride(id, d, ctx) {
  const reportFb = refId(d.reportId);
  const reportId = reportFb ? ctx.report(reportFb) : null;
  if (!reportId) return skipped(`report ${reportFb ?? '(missing)'} not migrated`);
  const validatorFb = refId(d.validatorId ?? d.userId);
  const validatorId = validatorFb ? ctx.user(validatorFb) : null;
  if (!validatorId) return skipped(`validator ${validatorFb ?? '(missing)'} not migrated`);
  const action = normalizeOverrideAction(d.action);
  if (!action) return skipped(`unknown action '${d.action}'`);
  return result({
    report_id: reportId,
    validator_id: validatorId,
    action,
    reason: asFreeText(d.reason),
    created_at: toIso(d.timestamp) ?? toIso(d.createdAt) ?? ctx.now,
  });
}

export function transformAlert(id, d, ctx) {
  const warnings = [];
  const title = asText(d.title);
  if (!title) return skipped('missing title');
  let severity = normalizeAlertSeverity(d.severity);
  if (!severity) {
    if (d.severity !== undefined) warnings.push(`unknown alert severity '${d.severity}' → info`);
    severity = 'info';
  }
  const creator = refId(d.createdBy);
  let createdBy = null;
  if (creator && creator.toLowerCase() !== 'admin') {
    createdBy = ctx.user(creator);
    if (!createdBy) warnings.push(`creator ${creator} not migrated; created_by set to null`);
  }
  const reportFb = refId(d.reportId);
  const reportId = reportFb ? ctx.report(reportFb) : null;
  if (reportFb && !reportId) warnings.push(`report ${reportFb} not migrated; report_id set to null`);
  const created = toIso(d.createdAt) ?? toIso(d.timestamp) ?? ctx.now;
  return result({
    title,
    message: asText(d.message ?? d.body),
    severity,
    target_lga: asText(d.targetLga ?? d.targetLGA ?? d.lga) || 'All',
    report_id: reportId,
    created_by: createdBy,
    is_active: asBool(d.isActive, true),
    created_at: created,
  }, warnings);
}

export function transformMessage(id, d, ctx) {
  const senderFb = refId(d.senderId ?? d.userId);
  const senderId = senderFb ? ctx.user(senderFb) : null;
  if (!senderId) return skipped(`sender ${senderFb ?? '(missing)'} not migrated`);
  const message = asFreeText(d.message ?? d.text);
  if (!message) return skipped('empty message');
  const sent = toIso(d.sentAt) ?? toIso(d.createdAt) ?? toIso(d.timestamp) ?? ctx.now;
  return result({
    chat_id: asText(d.chatId) || 'general',
    sender_id: senderId,
    sender_name: asFreeText(d.senderName),
    message,
    type: asText(d.type) || 'text',
    sent_at: sent,
    read: asBool(d.read, false),
    created_at: toIso(d.createdAt) ?? sent,
  });
}

export function transformContact(id, d, ctx) {
  const ownerFb = refId(d.userId);
  const userId = ownerFb ? ctx.user(ownerFb) : null;
  if (!userId) return skipped(`owner ${ownerFb ?? '(missing)'} not migrated`);
  const phone = asText(d.phone);
  if (!phone) return skipped('missing phone');
  return result({
    user_id: userId,
    name: asFreeText(d.name) || phone,
    role: asFreeText(d.role ?? d.relationship),
    phone,
    organization: asNullableFreeText(d.organization),
    lga: asNullableText(d.lga),
    category: asText(d.category) || 'other',
    is_available: asBool(d.isAvailable, true),
    created_at: toIso(d.createdAt) ?? ctx.now,
  });
}

export function transformKnowledge(id, d, ctx) {
  const title = asText(d.title);
  if (!title) return skipped('missing title');
  const image = cleanImageUrl(d.imageUrl);
  return result({
    title,
    content: asText(d.content),
    source: asText(d.source),
    category: asText(d.category) || 'General',
    hazard_type: asText(d.hazardType) || 'general',
    image_url: image ? ctx.url(image) : null,
    legacy_firebase_id: id,
    created_at: toIso(d.createdAt) ?? toIso(d.updatedAt) ?? ctx.now,
  });
}

export function transformAuthority(id, d, ctx) {
  const phone = asText(d.phone);
  if (!phone) return skipped('missing phone');
  const lga = asText(d.coverageLGA ?? d.coverageLga ?? d.coverage_lga ?? d.lga);
  if (!lga) return skipped('missing coverage LGA');
  return result({
    name: asText(d.name),
    organization: asNullableText(d.organization),
    phone,
    coverage_lga: lga,
    created_at: toIso(d.createdAt) ?? ctx.now,
  });
}

export function transformTrustedDevice(id, d, ctx) {
  const ownerFb = refId(d.userId);
  const userId = ownerFb ? ctx.user(ownerFb) : null;
  if (!userId) return skipped(`user ${ownerFb ?? '(missing)'} not migrated`);
  const fingerprint = asText(d.deviceFingerprint);
  if (!fingerprint) return skipped('missing deviceFingerprint');
  const lastUsed = toIso(d.lastUsed) ?? toIso(d.updatedAt) ?? ctx.now;
  return result({
    user_id: userId,
    device_fingerprint: fingerprint,
    device_name: asText(d.deviceName),
    trusted: asBool(d.trusted, true),
    last_used: lastUsed,
    created_at: toIso(d.createdAt) ?? lastUsed,
  });
}

export function transformLoginHistory(id, d, ctx) {
  const ownerFb = refId(d.userId);
  const userId = ownerFb ? ctx.user(ownerFb) : null;
  if (!userId) return skipped(`user ${ownerFb ?? '(missing)'} not migrated`);
  const occurred = toIso(d.timestamp) ?? toIso(d.createdAt) ?? ctx.now;
  return result({
    user_id: userId,
    success: asBool(d.success, false),
    device_fingerprint: asText(d.deviceFingerprint),
    device_name: asText(d.deviceName),
    risk_score: asInt(d.riskScore, 0),
    occurred_at: occurred,
    created_at: toIso(d.createdAt) ?? occurred,
  });
}

export function transformNdpaConsent(id, d, ctx) {
  const ownerFb = refId(d.uid ?? d.userId) ?? id;
  const userId = ctx.user(ownerFb);
  if (!userId) return skipped(`user ${ownerFb} not migrated`);
  const warnings = [];
  let version = asText(d.policyVersion);
  if (!version) {
    warnings.push('missing policyVersion → unknown');
    version = 'unknown';
  }
  return result({
    user_id: userId,
    consented_at: toIso(d.consentedAt) ?? toIso(d.createdAt) ?? ctx.now,
    policy_version: version,
    data_residency: asText(d.dataResidency),
    platform: asText(d.platform) || 'mobile',
    method: asText(d.method),
  }, warnings);
}

/** Stable-enough UUID generator, exported so the runner and tests share it. */
export function newUuid() {
  return randomUUID();
}
