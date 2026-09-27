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
//   ctx.userState(firebaseUid)→ that user's canonical profile state | null
//                               (optional; used only to disambiguate an LGA name)
//   ctx.now                   → ISO timestamp used as a last-resort default

import { randomUUID } from 'node:crypto';

import { builtinGuideFor } from './builtinContent.js';
import { NIGERIA_LGAS_BY_STATE } from './nigeria-lgas.js';

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

/**
 * Cut `text` to at most `max` characters (Unicode code points, as Postgres
 * char_length counts them), pushing a warning naming `field` when it had to.
 */
export function capText(text, max, field, warnings) {
  if (typeof text !== 'string') return text;
  const chars = Array.from(text);
  if (chars.length <= max) return text;
  warnings.push(`${field} truncated from ${chars.length} to ${max} characters`);
  return chars.slice(0, max).join('').trimEnd();
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

// verification_overrides.action allows 'approved', 'rejected' and 'verified'
// (20260926020000_workflow_hardening.sql).
export function normalizeOverrideAction(raw) {
  const value = asText(raw).toLowerCase();
  if (['approved', 'approve', 'validated', 'validate', 'resolved'].includes(value)) return 'approved';
  if (['rejected', 'reject', 'declined', 'decline'].includes(value)) return 'rejected';
  if (['verified', 'verify', 'acknowledged', 'acknowledge'].includes(value)) return 'verified';
  return null;
}

// Canonical state names, as reports.state stores them: 36 states + FCT. Taken
// from the same generated copy of lib/core/data/nigeria_locations_data.dart
// that the LGA lookups below use, so a state cannot be canonical here and
// unknown there (or vice versa).
export const NIGERIAN_STATES = Object.keys(NIGERIA_LGAS_BY_STATE);

const stateKey = (s) => s.toLowerCase().replace(/[^a-z]/g, '');

// Common alternative spellings → canonical name (keys as produced by stateKey).
const STATE_ALIASES = {
  nassarawa: 'Nasarawa',
  nasarrawa: 'Nasarawa',
  nassarrawa: 'Nasarawa',
  federalcapitalterritory: 'FCT',
  federalcapitalterritoryabuja: 'FCT',
  abuja: 'FCT',
  abujafct: 'FCT',
  fctabuja: 'FCT',
  crossrivers: 'Cross River',
  akwaibomm: 'Akwa Ibom',
  plateu: 'Plateau',
  platue: 'Plateau',
  benui: 'Benue',
};

const STATE_BY_KEY = new Map([
  ...NIGERIAN_STATES.map((s) => [stateKey(s), s]),
  ...Object.entries(STATE_ALIASES),
]);

/**
 * Map a free-text state ('benue', 'Benue State', 'NASSARAWA', 'Abuja',
 * 'Federal Capital Territory') to its canonical name, or null.
 */
export function normalizeNigerianState(raw) {
  const key = stateKey(asText(raw));
  if (!key) return null;
  return STATE_BY_KEY.get(key)
    ?? (key.endsWith('state') ? STATE_BY_KEY.get(key.slice(0, -'state'.length)) : undefined)
    ?? null;
}

// ── LGAs ─────────────────────────────────────────────────────────────────────
//
// Built from the generated copy of lib/core/data/nigeria_locations_data.dart,
// which is also what seeds public.nigeria_states / public.nigeria_lgas. Since
// 20260927080000 the database rejects an alert that names an LGA without a
// state, and rejects a (state, LGA) pair that is not in that table, so every
// row this module produces has to be resolved and spelled the same way.

const lgaKey = (s) => asText(s).toLowerCase();

// 'obi' -> [['Benue', 'Obi'], ['Nasarawa', 'Obi']]: every canonical
// (state, LGA) pair whose LGA name matches, case-insensitively.
const LGA_PAIRS_BY_NAME = new Map();
for (const [state, lgas] of Object.entries(NIGERIA_LGAS_BY_STATE)) {
  for (const lga of lgas) {
    const key = lgaKey(lga);
    if (!LGA_PAIRS_BY_NAME.has(key)) LGA_PAIRS_BY_NAME.set(key, []);
    LGA_PAIRS_BY_NAME.get(key).push([state, lga]);
  }
}

/**
 * Every canonical [state, lga] pair for an LGA name (case-insensitive).
 * Empty when the name is not an LGA of any state; more than one entry when the
 * name is ambiguous — 6 of the 770 names are (Bassa, Ifelodun, Irepodun,
 * Nasarawa, Obi, Surulere).
 */
export function lgaPairs(name) {
  return LGA_PAIRS_BY_NAME.get(lgaKey(name)) ?? [];
}

/** Whether an LGA name belongs to more than one state. */
export function isAmbiguousLga(name) {
  return lgaPairs(name).length > 1;
}

/**
 * The canonical spelling of [lga] within [state], or null when [state] has no
 * such LGA. Both arguments are matched case-insensitively.
 */
export function canonicalLga(state, lga) {
  return lgaPairs(lga).find(([s]) => s === state)?.[1] ?? null;
}

/** Whether a target_lga value is the 'every LGA' sentinel (the column's default). */
export function isAllLgas(value) {
  const text = asText(value);
  return text === '' || text.toLowerCase() === 'all';
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

/**
 * Rewrite a stored image reference through ctx.url first (so gs:// and
 * Firebase URLs of copied objects become Supabase URLs), then keep it only if
 * it is http(s). A gs:// reference that could not be rewritten is dropped
 * with a warning (the app cannot load it).
 */
export function imageUrl(value, ctx, warnings) {
  const text = asText(value);
  if (!text) return '';
  const rewritten = cleanImageUrl(ctx.url(text));
  if (!rewritten && warnings && /^gs:\/\//i.test(text)) {
    warnings.push(`image ${text} has no copied Supabase Storage object; dropped`);
  }
  return rewritten;
}

// ── Storage uploads ──────────────────────────────────────────────────────────

// Both buckets (20260925000000_init.sql): 5 MB, jpeg/png/webp/heic only.
export const STORAGE_ALLOWED_TYPES = ['image/jpeg', 'image/png', 'image/webp', 'image/heic'];
export const STORAGE_MAX_BYTES = 5 * 1024 * 1024;

const EXT_TYPES = { jpg: 'image/jpeg', jpeg: 'image/jpeg', jpe: 'image/jpeg', png: 'image/png', webp: 'image/webp', heic: 'image/heic' };
const TYPE_ALIASES = { 'image/jpg': 'image/jpeg', 'image/pjpeg': 'image/jpeg' };
const GENERIC_TYPES = new Set(['', 'application/octet-stream', 'binary/octet-stream', 'application/binary', 'image/*']);

/**
 * Decide how to upload a Storage object: { contentType } or { skip: reason }.
 * image/jpg → image/jpeg; a missing or generic type is inferred from the
 * extension; types the buckets refuse and objects over the size limit are
 * skipped. `metadata` is the Firebase object metadata ({ contentType, size }).
 */
export function storageUploadPlan(name, metadata = {}) {
  const size = Number(metadata?.size);
  if (Number.isFinite(size) && size > STORAGE_MAX_BYTES) {
    return { skip: `larger than the ${STORAGE_MAX_BYTES / 1048576} MB bucket limit (${(size / 1048576).toFixed(1)} MB)` };
  }
  const recorded = asText(metadata?.contentType).toLowerCase().split(';')[0].trim();
  let contentType = TYPE_ALIASES[recorded] ?? recorded;
  if (GENERIC_TYPES.has(contentType)) {
    const ext = String(name ?? '').split('/').pop().split('.').slice(1).pop()?.toLowerCase();
    contentType = (ext && EXT_TYPES[ext]) ?? '';
    if (!contentType) {
      return { skip: `content type ${recorded || '(missing)'} and extension ${ext ? `'.${ext}'` : '(none)'} not allowed by the bucket (${STORAGE_ALLOWED_TYPES.join(', ')})` };
    }
  }
  if (!STORAGE_ALLOWED_TYPES.includes(contentType)) {
    return { skip: `content type ${contentType} not allowed by the bucket (${STORAGE_ALLOWED_TYPES.join(', ')})` };
  }
  return { contentType };
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
    profile_image_url: imageUrl(d.profileImageUrl || a.photoURL, ctx, warnings),
    registration_code: asNullableText(d.registrationCode),
    last_login_at: toIso(d.lastLoginAt) ?? toIso(a.metadata?.lastSignInTime),
    legacy_firebase_uid: uid,
  };
  if (created) profile.created_at = created;
  if (!doc) warnings.push('no Firestore users document; profile uses defaults');
  if (!authRecord) warnings.push('no Firebase Auth record; created from Firestore document only');
  return { ...result({ auth, profile }, warnings), kind };
}

export const REPORT_TEXT_LIMITS = {
  hazard_type: 60,
  description: 2000,
  location: 500,
  location_details: 500,
  address: 500,
  ward: 120,
  lga: 120,
  state: 120,
};
export const REPORT_MAX_IMAGES = 10;
// messages_before_write (20260927000000_security_hardening.sql) cuts
// messages.message to 2000 characters.
export const MESSAGE_MAX_CHARS = 2000;

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
  let imageUrls = images.map((u) => imageUrl(u, ctx, warnings)).filter(Boolean);
  if (imageUrls.length > REPORT_MAX_IMAGES) {
    warnings.push(`${imageUrls.length} images; only the first ${REPORT_MAX_IMAGES} kept`);
    imageUrls = imageUrls.slice(0, REPORT_MAX_IMAGES);
  }
  // Length limits: reports_*_len checks in 20260927000000_security_hardening.sql.
  const cap = (text, field) => capText(text, REPORT_TEXT_LIMITS[field], field, warnings);

  const updatedByUid = refId(d.updatedBy);
  return result({
    user_id: userId,
    reporter_name: asNullableFreeText(d.reporterName),
    hazard_type: cap(asText(d.hazardType) || asText(d.type) || 'unknown', 'hazard_type'),
    severity,
    latitude: asNumber(d.latitude) ?? asNumber(geo?.latitude ?? geo?._latitude),
    longitude: asNumber(d.longitude) ?? asNumber(geo?.longitude ?? geo?._longitude),
    location_details: cap(asFreeText(d.locationDetails) || locationText, 'location_details'),
    location: cap(locationText || asFreeText(d.locationDetails), 'location'),
    address: cap(asFreeText(d.address), 'address'),
    ward: cap(asText(d.ward), 'ward'),
    lga: cap(lga, 'lga'),
    state: cap(asText(d.state), 'state'),
    description: cap(asFreeText(d.description), 'description'),
    submitted_at: submitted ?? ctx.now,
    image_urls: imageUrls,
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
  const action = normalizeOverrideAction(d.action);
  if (!action) return skipped(`unknown action '${d.action}'`);
  // validator_id is nullable (audit rows outlive their validator), so the
  // override is kept even when the validator was not migrated.
  const warnings = [];
  const validatorFb = refId(d.validatorId ?? d.userId);
  const validatorId = validatorFb ? ctx.user(validatorFb) : null;
  if (!validatorId) warnings.push(`validator ${validatorFb ?? '(missing)'} not migrated; validator_id set to null`);
  return result({
    report_id: reportId,
    validator_id: validatorId,
    action,
    reason: asFreeText(d.reason),
    created_at: toIso(d.timestamp) ?? toIso(d.createdAt) ?? ctx.now,
  }, warnings);
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

  const target = alertTarget(d, creator, ctx, warnings);
  if (target.skip) return skipped(`alert '${title}': ${target.skip}`);

  const created = toIso(d.createdAt) ?? toIso(d.timestamp) ?? ctx.now;
  return result({
    title,
    message: asText(d.message ?? d.body),
    severity,
    target_lga: target.lga,
    target_state: target.state,
    report_id: reportId,
    created_by: createdBy,
    is_active: asBool(d.isActive, true),
    created_at: created,
  }, warnings);
}

/**
 * The (target_state, target_lga) an alert document means, or a skip reason.
 *
 * Firestore alerts only ever carried an LGA name, and since 20260927080000 the
 * database will not accept one without its state — an LGA name alone can mean
 * two different places. So the state is resolved here from the canonical LGA
 * table, and an alert whose target still cannot be pinned to one place is
 * skipped with a reason naming it. Nothing is guessed, and an alert is never
 * widened to 'All' or to a whole state to make it fit: that would broadcast to
 * people it was never addressed to.
 *
 * Returns { state, lga } or { skip }.
 */
function alertTarget(d, creatorFb, ctx, warnings) {
  const rawLga = asText(d.targetLga ?? d.targetLGA ?? d.lga);
  const rawState = asText(d.targetState ?? d.targetLgaState ?? d.state);
  const state = normalizeNigerianState(rawState);
  if (rawState && !state) {
    return { skip: `target state '${rawState}' is not a Nigerian state; re-create the alert in the admin panel with a state from the list` };
  }

  // Every LGA (of `state`, or of the whole country when the alert names none).
  if (isAllLgas(rawLga)) return { state, lga: 'All' };

  const pairs = lgaPairs(rawLga);
  if (pairs.length === 0) {
    return { skip: `target LGA '${rawLga}' is not an LGA of any Nigerian state; re-create the alert in the admin panel with an LGA from the list` };
  }

  if (state) {
    const lga = canonicalLga(state, rawLga);
    if (!lga) {
      return { skip: `target LGA '${rawLga}' is not an LGA of ${state} (it is in ${pairs.map(([s]) => s).join(', ')})` };
    }
    return { state, lga };
  }

  if (pairs.length === 1) {
    const [only, lga] = pairs[0];
    return { state: only, lga };
  }

  // Ambiguous name, no state on the alert: the only honest tiebreak is the
  // state of whoever published it.
  const states = pairs.map(([s]) => s);
  const creatorState = creatorFb ? (ctx.userState?.(creatorFb) ?? null) : null;
  if (creatorState && states.includes(creatorState)) {
    warnings.push(`target LGA '${rawLga}' exists in ${states.join(' and ')}; resolved to ${creatorState} from the alert creator's profile state`);
    return { state: creatorState, lga: canonicalLga(creatorState, rawLga) };
  }
  return {
    skip: `target LGA '${rawLga}' exists in more than one state (${states.join(', ')}) and the alert names none`
      + (creatorState
        ? `; its creator's profile state (${creatorState}) is not one of them`
        : creatorFb
          ? `; its creator (${creatorFb}) has no usable profile state either`
          : '; the alert has no creator whose profile state could disambiguate it')
      + '. Re-create the alert in the admin panel with the state you meant',
  };
}

export function transformMessage(id, d, ctx) {
  const senderFb = refId(d.senderId ?? d.userId);
  const senderId = senderFb ? ctx.user(senderFb) : null;
  if (!senderId) return skipped(`sender ${senderFb ?? '(missing)'} not migrated`);
  const warnings = [];
  const message = capText(asFreeText(d.message ?? d.text), MESSAGE_MAX_CHARS, 'message', warnings);
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
  }, warnings);
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
  // The schema seeds the app's built-in guides (fixed ids, no legacy id);
  // importing Firestore copies of them would list each guide twice.
  const builtin = builtinGuideFor(title);
  if (builtin) return skipped(`replaced by built-in guide '${builtin}'`);
  const warnings = [];
  const image = imageUrl(d.imageUrl, ctx, warnings);
  return result({
    title,
    content: asText(d.content),
    source: asText(d.source),
    category: asText(d.category) || 'General',
    hazard_type: asText(d.hazardType) || 'general',
    image_url: image || null,
    legacy_firebase_id: id,
    created_at: toIso(d.createdAt) ?? toIso(d.updatedAt) ?? ctx.now,
  }, warnings);
}

/**
 * An SMS contact for one (coverage_state, coverage_lga).
 *
 * Since migration 20260927090000 coverage_state is NOT NULL and
 * (coverage_state, coverage_lga) is a foreign key into public.nigeria_lgas, so
 * a row without a state, with an invented state, or with an LGA that is not in
 * the state it claims, is rejected outright. Firestore authorities often
 * carried only an LGA name, so the state is resolved here from the canonical
 * LGA table (src/nigeria-lgas.js), exactly as transformAlert does for alert
 * targets, and both names are re-spelled canonically.
 *
 * Nothing is ever guessed. 6 of the 770 LGA names belong to two states
 * (Bassa, Ifelodun, Irepodun, Nasarawa, Obi, Surulere); a contact with such a
 * name and no state is SKIPPED with a warning naming it, its phone and the
 * candidate states, so an operator can add it by hand with the state that desk
 * actually serves. Picking one would text the wrong emergency desk.
 */
export function transformAuthority(id, d, ctx) {
  const phone = asText(d.phone);
  if (!phone) return skipped('missing phone');
  const rawLga = asText(d.coverageLGA ?? d.coverageLga ?? d.coverage_lga ?? d.lga);
  if (!rawLga) return skipped('missing coverage LGA');
  const who = `authority '${asText(d.name) || '(no name)'}' (${phone})`;

  // "Benue State" / "benue" → "Benue", "Abuja" → "FCT": the canonical names
  // reports.state holds, which coverage_state is matched against.
  const rawState = asText(d.coverageState ?? d.coverage_state ?? d.state);
  const state = normalizeNigerianState(rawState);
  if (rawState && !state) {
    return skipped(`${who}: state '${rawState}' is not a Nigerian state; add it on the Authorities page with a state from the list`);
  }

  const pairs = lgaPairs(rawLga);
  if (pairs.length === 0) {
    return skipped(`${who}: coverage LGA '${rawLga}' is not an LGA of any Nigerian state; add it on the Authorities page with an LGA from the list`);
  }

  let coverage;
  if (state) {
    const lga = canonicalLga(state, rawLga);
    if (!lga) {
      return skipped(`${who}: coverage LGA '${rawLga}' is not an LGA of ${state} (it is in ${pairs.map(([s]) => s).join(', ')})`);
    }
    coverage = { state, lga };
  } else if (pairs.length === 1) {
    // 764 of the 770 names identify one place: the contact already covered
    // exactly that place, so filling the state in changes nothing about who is
    // texted.
    const [only, lga] = pairs[0];
    coverage = { state: only, lga };
  } else {
    const states = pairs.map(([s]) => s).join(', ');
    return skipped(
      `${who}: coverage LGA '${rawLga}' exists in more than one state (${states}) and the contact names none.`
      + ` Add it on the Authorities page under the state that desk actually serves — it must not be texted for the other one`,
    );
  }

  return result({
    name: asText(d.name),
    organization: asNullableText(d.organization),
    phone,
    coverage_lga: coverage.lga,
    coverage_state: coverage.state,
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
