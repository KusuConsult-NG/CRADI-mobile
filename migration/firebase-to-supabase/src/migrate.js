#!/usr/bin/env node
// One-off Firebase (ewer-8f788) → Supabase data migration for CRADI / EWER.
// Dry run by default; pass --apply to write. See README.md.

import fs from 'node:fs';
import path from 'node:path';
import { randomBytes } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';

import {
  loadDotEnv, firebaseClients, supabaseClient, readCollection, listFirebaseAuthUsers,
} from './clients.js';
import { IN_CHUNK, must, selectAll } from './db.js';
import { BACKEND_STOPPED_FLAG, applyPreflight, suppressSideEffects } from './sideEffects.js';
import { MigrationState } from './state.js';
import {
  isUuid, isPhoneEmail, rewriteUrl, storageTargetFor, FIREBASE_STORAGE_PREFIXES,
  transformUser, transformReport, transformVerification, transformVerificationOverride,
  transformAlert, transformMessage, transformContact, transformKnowledge, transformAuthority,
  transformTrustedDevice, transformLoginHistory, transformNdpaConsent,
} from './transform.js';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

// Import order. 'storage' runs between auth-user creation and the profile
// patch so profile_image_url can be rewritten. Alerts run after reports so an
// alert's reportId can be resolved (alert inserts are made inactive first, so
// no outbox events either way).
const STEPS = [
  'users', 'storage', 'knowledge_base', 'authorities', 'reports', 'alerts', 'verifications',
  'verification_overrides', 'messages', 'contacts', 'trusted_devices', 'login_history', 'ndpa_consents',
];

const BAN_FOREVER = '876000h';
const CHUNK = 200;

// ── CLI ──────────────────────────────────────────────────────────────────────

const { values: args } = parseArgs({
  options: {
    apply: { type: 'boolean', default: false },
    [BACKEND_STOPPED_FLAG]: { type: 'boolean', default: false },
    only: { type: 'string' },
    'skip-storage': { type: 'boolean', default: false },
    'send-password-resets': { type: 'boolean', default: false },
    'state-file': { type: 'string' },
    samples: { type: 'string', default: '2' },
    help: { type: 'boolean', short: 'h', default: false },
  },
});

if (args.help) {
  console.log(`Usage: node src/migrate.js [--apply --${BACKEND_STOPPED_FLAG}] [--only=users,reports,...] [--skip-storage]
                           [--send-password-resets] [--state-file=path] [--samples=N]

Steps (in order): ${STEPS.join(', ')}
--only=none runs no import step (use with --send-password-resets).
Without --apply nothing is written (dry run).
--apply requires --${BACKEND_STOPPED_FLAG}: the backend worker must be stopped
(Railway: scaled to 0) during the import.`);
  process.exit(0);
}

const preflightError = applyPreflight(args);
if (preflightError) {
  console.error(preflightError);
  process.exit(2);
}

loadDotEnv(ROOT);
const APPLY = args.apply;
const SKIP_STORAGE = args['skip-storage'];
const SAMPLES = Number(args.samples) || 0;
// --only=none runs no import step (e.g. with --send-password-resets alone).
const only = args.only !== undefined
  ? new Set(args.only.split(',').map((s) => s.trim()).filter((s) => s && s !== 'none')
    .map((s) => (s === 'profiles' ? 'users' : s)))
  : null;
if (only) {
  const unknown = [...only].filter((s) => !STEPS.includes(s));
  if (unknown.length) {
    console.error(`Unknown --only value(s): ${unknown.join(', ')}. Valid: ${STEPS.join(', ')}`);
    process.exit(2);
  }
}
const inScope = (step) => (!only || only.has(step)) && !(step === 'storage' && SKIP_STORAGE);

// ── Reporting ────────────────────────────────────────────────────────────────

class RunReport {
  constructor() {
    this.tables = new Map();
    this.notes = [];
  }

  t(name) {
    if (!this.tables.has(name)) {
      this.tables.set(name, { source: 0, ready: 0, written: 0, target: null, skipped: [], warnings: [], samples: [] });
    }
    return this.tables.get(name);
  }

  skip(table, id, reason) { this.t(table).skipped.push({ id, reason }); }
  warn(table, id, reason) { this.t(table).warnings.push({ id, reason }); }
  sample(table, row) { const t = this.t(table); if (t.samples.length < SAMPLES) t.samples.push(row); }

  printSamples() {
    for (const [name, t] of this.tables) {
      if (!t.samples.length) continue;
      console.log(`\n── Sample transformed rows: ${name}`);
      for (const s of t.samples) console.log(JSON.stringify(s, null, 2));
    }
  }

  print() {
    console.log('\n══ Validation report ═══════════════════════════════════════════════════════');
    const header = ['table', 'source', 'ready', 'skipped', APPLY ? 'written' : '-', 'target rows'];
    const rows = [...this.tables].map(([name, t]) => [
      name, t.source, t.ready, t.skipped.length, APPLY ? t.written : '', t.target ?? '',
    ]);
    const widths = header.map((h, i) => Math.max(String(h).length, ...rows.map((r) => String(r[i]).length)));
    const line = (r) => r.map((c, i) => String(c).padEnd(widths[i])).join('  ');
    console.log(line(header));
    console.log(widths.map((w) => '-'.repeat(w)).join('  '));
    rows.forEach((r) => console.log(line(r)));

    for (const [kind, key] of [['Skipped', 'skipped'], ['Warnings', 'warnings']]) {
      for (const [name, t] of this.tables) {
        if (!t[key].length) continue;
        console.log(`\n${kind} — ${name} (${t[key].length}):`);
        const groups = new Map();
        for (const p of t[key]) {
          const g = p.reason.replace(/\b[A-Za-z0-9_-]{16,}\b/g, '<id>');
          if (!groups.has(g)) groups.set(g, []);
          groups.get(g).push(p.id);
        }
        for (const [reason, ids] of groups) {
          const eg = ids.slice(0, 3).join(', ') + (ids.length > 3 ? ', …' : '');
          console.log(`  ${String(ids.length).padStart(5)} × ${reason}   [${eg}]`);
        }
      }
    }
    for (const n of this.notes) console.log(`\nNote: ${n}`);
  }

  writeJson(file) {
    const out = Object.fromEntries([...this.tables].map(([k, v]) => [k, { ...v, samples: undefined }]));
    fs.writeFileSync(file, JSON.stringify({ apply: APPLY, notes: this.notes, tables: out }, null, 2));
  }
}

// ── Supabase helpers ─────────────────────────────────────────────────────────

async function countRows(sb, table, apply = (q) => q) {
  const { count, error } = await apply(sb.from(table).select('*', { count: 'exact', head: true }));
  if (error) return `error: ${error.message}`;
  return count;
}

async function mapLimit(items, limit, fn) {
  const results = new Array(items.length);
  let next = 0;
  const workers = Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (next < items.length) {
      const i = next++;
      results[i] = await fn(items[i], i);
    }
  });
  await Promise.all(workers);
  return results;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/**
 * Upsert rows in chunks. A failing chunk is retried row by row so one bad row
 * does not block the rest; failures are reported as skips.
 * `entries` is [{ sourceId, row }].
 */
async function upsertEntries(sb, report, table, entries, options) {
  let written = 0;
  for (let i = 0; i < entries.length; i += CHUNK) {
    const chunk = entries.slice(i, i + CHUNK);
    const { error } = await sb.from(table).upsert(chunk.map((e) => e.row), options);
    if (!error) {
      written += chunk.length;
      continue;
    }
    for (const e of chunk) {
      const { error: rowError } = await sb.from(table).upsert([e.row], options);
      if (rowError) report.skip(table, e.sourceId, `write failed: ${rowError.message}`);
      else written += 1;
    }
  }
  return written;
}

/** Keep the last entry per natural key (avoids "ON CONFLICT … affect row a second time"). */
function dedupe(report, table, entries, keyFn) {
  const byKey = new Map();
  for (const e of entries) {
    const key = keyFn(e.row);
    if (byKey.has(key)) report.warn(table, byKey.get(key).sourceId, `duplicate of ${e.sourceId} on unique key; keeping the later one`);
    byKey.set(key, e);
  }
  return [...byKey.values()];
}

// ── Main ─────────────────────────────────────────────────────────────────────

async function main() {
  const report = new RunReport();
  const stateFile = path.resolve(args['state-file'] ?? path.join(ROOT, 'migration-state.json'));
  const state = new MigrationState(stateFile);
  const now = new Date().toISOString();

  console.log(APPLY
    ? '══ APPLY — writing to Supabase ══'
    : '══ DRY RUN — nothing will be written (pass --apply to write) ══');

  const fb = firebaseClients();
  const sb = supabaseClient(process.env, { required: APPLY || args['send-password-resets'] });
  console.log(`Firebase project: ${fb.projectId}   Supabase: ${sb ? process.env.SUPABASE_URL : '(not configured — offline dry run)'}`);
  console.log(`State file: ${stateFile}`);
  if (only) console.log(`Only: ${[...only].join(', ') || '(no import steps)'}`);
  if (SKIP_STORAGE) console.log('Storage copy skipped; URLs of objects not copied by an earlier run stay on Firebase.');

  // Seed id maps from Supabase so a lost state file never causes duplicates.
  if (sb) {
    const profiles = await selectAll(sb, 'profiles', 'id,legacy_firebase_uid', (q) => q.not('legacy_firebase_uid', 'is', null));
    for (const p of profiles) state.data.users[p.legacy_firebase_uid] = p.id;
    const reports = await selectAll(sb, 'reports', 'id,legacy_firebase_id', (q) => q.not('legacy_firebase_id', 'is', null));
    for (const r of reports) state.setId('reports', r.legacy_firebase_id, r.id);
  }

  // ── Read Firebase ──────────────────────────────────────────────────────────
  const authUsers = await listFirebaseAuthUsers(fb.auth);
  const userDocs = await readCollection(fb.db, 'users');
  console.log(`Firebase Auth users: ${authUsers.length}; Firestore users docs: ${userDocs.length}`);

  const authByUid = new Map(authUsers.map((u) => [u.uid, u]));
  const docByUid = new Map(userDocs.map((d) => [d.id, d.data]));
  const allUids = [...new Set([...authByUid.keys(), ...docByUid.keys()])].sort();

  // Users that would be migrated (for dry-run reference resolution).
  const migratableUids = new Set(
    allUids.filter((uid) => !transformUser(uid, authByUid.get(uid), docByUid.get(uid), { url: (u) => u }).skip),
  );
  const resolveUser = (uid) => {
    if (!uid) return null;
    if (state.data.users[uid]) return state.data.users[uid];
    if (!APPLY && migratableUids.has(uid)) return `dry-run:user:${uid}`;
    return null;
  };

  let reportSourceIds = new Set();
  const urlMap = new Map(Object.entries(state.data.storage));
  const ctx = {
    now,
    user: resolveUser,
    report: (id) => state.getId('reports', id) ?? (!APPLY && reportSourceIds.has(id) ? `dry-run:report:${id}` : null),
    // Objects copied by any run (recorded in the state file) are always
    // rewritten; --skip-storage only skips copying, so uncopied objects keep
    // their Firebase URLs.
    url: (u) => rewriteUrl(u, urlMap),
  };
  const planUser = (uid) => transformUser(uid, authByUid.get(uid), docByUid.get(uid), ctx);
  const plans = new Map(allUids.map((uid) => [uid, planUser(uid)]));

  // ── Side-effect baseline ───────────────────────────────────────────────────
  let outboxBaseline = null;
  const touchedReportIds = new Set();
  const touchedAlertIds = new Set();
  const suppressed = { outbox: 0, escalations: 0 };
  // Run after every writing step (and in `finally`), so events queued for
  // imported rows are neutralised within one step, not only at the very end.
  const suppress = async () => {
    if (!APPLY) return;
    const res = await suppressSideEffects(sb, { baseline: outboxBaseline, reportIds: touchedReportIds, alertIds: touchedAlertIds });
    suppressed.outbox += res.outbox;
    suppressed.escalations += res.escalations;
    res.errors.forEach((e) => console.error(`!! ${e}`));
  };
  if (APPLY) {
    const rows = must(await sb.from('notification_outbox').select('id').order('id', { ascending: false }).limit(1), 'outbox baseline');
    outboxBaseline = rows[0]?.id ?? 0;
    console.log(`notification_outbox baseline id: ${outboxBaseline}`);
    state.data.runs.push({ startedAt: now, outboxBaseline, only: only ? [...only] : null });
    state.save();
  }

  try {
    // ── 1. Users (auth accounts) ────────────────────────────────────────────
    if (inScope('users')) {
      const r = report.t('profiles');
      r.source = allUids.length;
      for (const [uid, t] of plans) {
        if (t.skip) { report.skip('profiles', uid, t.skip); continue; }
        t.warnings.forEach((w) => report.warn('profiles', uid, w));
        r.ready += 1;
        report.sample('profiles', { firebase_uid: uid, kind: t.kind, auth: t.row.auth, profile: t.row.profile });
      }
      if (!APPLY) {
        const owner = new Map();
        for (const [uid, t] of plans) {
          if (t.skip) continue;
          const key = t.row.auth.email ?? t.row.auth.phone;
          if (owner.has(key)) report.warn('profiles', uid, `same email/phone as Firebase user ${owner.get(key)}; would be merged into that account`);
          else owner.set(key, uid);
        }
      }
      const pending = [...plans].filter(([uid, t]) => !t.skip && !state.data.users[uid]);
      console.log(`Auth users: ${r.ready - pending.length} already migrated, ${pending.length} to create/link.`);
      if (APPLY && pending.length) await createAuthUsers(sb, state, report, pending);
    }

    // ── 2. Storage ──────────────────────────────────────────────────────────
    if (inScope('storage')) await copyStorage(fb, sb, state, report, urlMap, resolveUser);

    // ── 3. Profile patch (+ bans) ───────────────────────────────────────────
    // Recompute the plans so profile_image_url picks up the copied objects.
    if (inScope('users')) await patchProfiles(sb, state, report, allUids.map((uid) => [uid, planUser(uid)]));

    // ── 4. Simple content tables ────────────────────────────────────────────
    if (inScope('knowledge_base')) {
      await importCollection({ fb, sb, state, report, ctx, source: 'knowledge_base', table: 'knowledge_base',
        transform: transformKnowledge, strategy: 'legacy' });
    }
    if (inScope('authorities')) {
      await importCollection({ fb, sb, state, report, ctx, source: 'authorities', table: 'authorities',
        transform: transformAuthority, strategy: 'state' });
    }

    // ── 5. Reports → alerts → verifications → overrides ─────────────────────
    let reportEntries = null;
    const needReports = inScope('reports') || inScope('verifications');
    if (needReports) {
      const docs = await readCollection(fb.db, 'reports');
      reportSourceIds = new Set(docs.map((d) => d.id));
      // Assign ids: existing mapping → Firestore id when it is a UUID → new uuid.
      for (const d of docs) state.idFor('reports', d.id, isUuid(d.id) ? d.id.toLowerCase() : null);
      if (APPLY) state.save();
      reportEntries = buildEntries(report, inScope('reports') ? 'reports' : null, docs, transformReport, ctx,
        (d, row) => ({ ...row, id: state.getId('reports', d.id) }));
    }
    if (inScope('reports') && APPLY) {
      report.t('reports').written += await upsertEntries(sb, report, 'reports', reportEntries, { onConflict: 'id' });
      reportEntries.forEach((e) => touchedReportIds.add(e.row.id));
      await suppress();
    }

    if (inScope('alerts')) {
      await importAlerts({ fb, sb, state, report, ctx, touched: touchedAlertIds });
      await suppress();
    }

    if (inScope('verifications')) {
      const entries = await importCollection({ fb, sb, state, report, ctx, source: 'verifications', table: 'verifications',
        transform: transformVerification, strategy: 'natural',
        upsert: { onConflict: 'report_id,verifier_id', ignoreDuplicates: true },
        key: (r) => `${r.report_id}|${r.verifier_id}` });
      // The verification trigger can change a report's status (→ report_status_changed).
      if (APPLY) entries.forEach((e) => touchedReportIds.add(e.row.report_id));
      await suppress();
    }

    // Final report state: the verification trigger recounts and may flip
    // status, and the insert trigger rewrites escalation fields. Re-apply
    // the Firestore values to every report that exists in Supabase.
    if (APPLY && reportEntries) {
      await finalizeReports(sb, report, reportEntries, touchedReportIds);
      await suppress();
    }

    if (inScope('verification_overrides')) {
      await importCollection({ fb, sb, state, report, ctx, source: 'verification_overrides',
        table: 'verification_overrides', transform: transformVerificationOverride, strategy: 'state' });
    }

    // ── 6. Remaining per-user tables ────────────────────────────────────────
    if (inScope('messages')) {
      await importCollection({ fb, sb, state, report, ctx, source: 'messages', table: 'messages',
        transform: transformMessage, strategy: 'state' });
    }
    if (inScope('contacts')) {
      await importCollection({ fb, sb, state, report, ctx, source: 'contacts', table: 'contacts',
        transform: transformContact, strategy: 'state' });
    }
    if (inScope('trusted_devices')) {
      await importCollection({ fb, sb, state, report, ctx, source: 'trusted_devices', table: 'trusted_devices',
        transform: transformTrustedDevice, strategy: 'natural',
        upsert: { onConflict: 'user_id,device_fingerprint' }, key: (r) => `${r.user_id}|${r.device_fingerprint}` });
    }
    if (inScope('login_history')) {
      await importCollection({ fb, sb, state, report, ctx, source: 'login_history', table: 'login_history',
        transform: transformLoginHistory, strategy: 'state' });
    }
    if (inScope('ndpa_consents')) {
      await importCollection({ fb, sb, state, report, ctx, source: 'ndpa_consents', table: 'ndpa_consents',
        transform: transformNdpaConsent, strategy: 'natural', upsert: { onConflict: 'user_id' }, key: (r) => r.user_id });
    }
  } finally {
    if (APPLY) {
      state.save();
      await suppress();
      report.notes.push(`Marked ${suppressed.outbox} notification_outbox event(s) for imported reports/alerts as processed (last_error 'migration import').`);
      report.notes.push(`Marked ${suppressed.escalations} scheduled_escalations created for imported reports as skipped.`);
    }
  }

  // ── 7. Password resets ─────────────────────────────────────────────────────
  if (args['send-password-resets']) await sendPasswordResets(sb, state, report, plans);

  // ── 8. Validation ──────────────────────────────────────────────────────────
  report.printSamples();
  if (sb) {
    for (const [name] of report.tables) {
      if (name === 'storage' || name === 'password_resets') continue;
      const filter = name === 'profiles' ? (q) => q.not('legacy_firebase_uid', 'is', null)
        : ['reports', 'knowledge_base'].includes(name) ? (q) => q.not('legacy_firebase_id', 'is', null)
          : undefined;
      report.t(name).target = await countRows(sb, name, filter);
    }
    report.notes.push('"target rows" counts all rows in the Supabase table (profiles/reports/knowledge_base: rows with a legacy id).');
  }
  report.print();
  const outFile = path.join(ROOT, `migration-report-${now.replace(/[:.]/g, '-')}.json`);
  report.writeJson(outFile);
  console.log(`\nFull report: ${outFile}`);
  if (!APPLY) console.log('\nDry run complete. Re-run with --apply to write.');
}

// ── Users ────────────────────────────────────────────────────────────────────

async function indexSupabaseUsers(sb) {
  const byEmail = new Map();
  const byPhone = new Map();
  for (let page = 1; ; page++) {
    const data = must(await sb.auth.admin.listUsers({ page, perPage: 1000 }), 'list Supabase users');
    for (const u of data.users) {
      if (u.email) byEmail.set(u.email.toLowerCase(), u.id);
      if (u.phone) byPhone.set(u.phone.replace(/^\+/, ''), u.id);
    }
    if (data.users.length < 1000) break;
  }
  return { byEmail, byPhone };
}

async function createAuthUsers(sb, state, report, pending) {
  let index = await indexSupabaseUsers(sb);
  const lookup = (auth) => (auth.email ? index.byEmail.get(auth.email) : index.byPhone.get(auth.phone.replace(/^\+/, '')));
  const claimed = new Map(Object.entries(state.data.users).map(([uid, id]) => [id, uid]));
  let created = 0;
  let linked = 0;

  await mapLimit(pending, 4, async ([uid, t]) => {
    const { auth } = t.row;
    let id = lookup(auth);
    if (id) {
      linked += 1;
      report.warn('profiles', uid, 'Supabase user with this email/phone already existed; reused');
    } else {
      const { data, error } = await sb.auth.admin.createUser({ ...auth, password: randomBytes(24).toString('base64url') });
      if (error) {
        if (/exists|already/i.test(`${error.code} ${error.message}`)) {
          index = await indexSupabaseUsers(sb);
          id = lookup(auth);
          if (id) { linked += 1; report.warn('profiles', uid, 'Supabase user already existed; reused'); }
        }
        if (!id) { report.skip('profiles', uid, `createUser failed: ${error.message}`); return; }
      } else {
        id = data.user.id;
        created += 1;
      }
    }
    if (claimed.has(id) && claimed.get(id) !== uid) {
      report.warn('profiles', uid, `same email/phone as Firebase user ${claimed.get(id)}; records merged into that account`);
    } else {
      claimed.set(id, uid);
    }
    state.data.users[uid] = id;
    state.save();
  });
  console.log(`Auth users: created ${created}, linked to existing ${linked}.`);
}

async function patchProfiles(sb, state, report, plans) {
  if (!APPLY) return;
  const claimed = new Set();
  const jobs = [];
  for (const [uid, t] of plans) {
    const id = state.data.users[uid];
    if (t.skip || !id) continue;
    if (claimed.has(id)) continue; // merged duplicate: the first Firebase user's profile wins
    claimed.add(id);
    jobs.push({ uid, id, profile: t.row.profile });
  }
  let written = 0;
  let banned = 0;
  await mapLimit(jobs, 8, async ({ uid, id, profile }) => {
    const { error } = await sb.from('profiles').update(profile).eq('id', id);
    if (error) { report.skip('profiles', uid, `profile update failed: ${error.message}`); return; }
    written += 1;
    if (profile.is_disabled) {
      const { error: banError } = await sb.auth.admin.updateUserById(id, { ban_duration: BAN_FOREVER });
      if (banError) report.warn('profiles', uid, `ban failed: ${banError.message}`);
      else banned += 1;
    }
  });
  report.t('profiles').written = written;
  console.log(`Profiles updated: ${written}; disabled users banned: ${banned}.`);
}

// ── Reports finalize ─────────────────────────────────────────────────────────

// Workflow columns that triggers may have rewritten during import:
//   reports_before_insert   escalation_scheduled_at / escalation_status (also on
//                           the INSERT … ON CONFLICT path, so an upsert cannot
//                           restore them — hence plain UPDATEs here)
//   verifications_after_insert  verification_count, status, verified_at, auto_validated
const FINAL_REPORT_COLUMNS = [
  'status', 'verification_count', 'verified_at', 'auto_validated', 'approved_at', 'rejected_at',
  'rejection_reason', 'escalated', 'escalated_at', 'escalation_reason', 'escalation_scheduled_at',
  'escalation_status',
];

async function finalizeReports(sb, report, entries, touched) {
  const inDb = new Set((await selectAll(sb, 'reports', 'id')).map((r) => r.id));
  const present = entries.filter((e) => inDb.has(e.row.id));
  let done = 0;
  await mapLimit(present, 8, async (e) => {
    const patch = Object.fromEntries(FINAL_REPORT_COLUMNS.map((c) => [c, e.row[c]]));
    const { error } = await sb.from('reports').update(patch).eq('id', e.row.id);
    if (error) report.warn('reports', e.sourceId, `finalize failed: ${error.message}`);
    else done += 1;
    touched.add(e.row.id);
  });
  console.log(`Finalized status/verification_count/escalation fields on ${done} report(s).`);
}

// ── Storage ──────────────────────────────────────────────────────────────────

const EXT_TYPES = { jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png', webp: 'image/webp', heic: 'image/heic' };

async function copyStorage(fb, sb, state, report, urlMap, resolveUser) {
  const r = report.t('storage');
  const files = [];
  for (const prefix of FIREBASE_STORAGE_PREFIXES) {
    const [list] = await fb.bucket.getFiles({ prefix: `${prefix}/` });
    files.push(...list.filter((f) => !f.name.endsWith('/')));
  }
  r.source = files.length;
  let bytes = 0;
  const todo = [];
  for (const f of files) {
    const target = storageTargetFor(f.name, resolveUser);
    if (!target) { report.skip('storage', f.name, 'owner not migrated or unexpected path'); continue; }
    r.ready += 1;
    bytes += Number(f.metadata?.size ?? 0);
    report.sample('storage', { from: f.name, to: `${target.bucket}/${target.path}` });
    if (state.data.storage[f.name]) continue;
    todo.push({ f, target });
  }
  console.log(`Storage: ${files.length} objects (${(bytes / 1e6).toFixed(1)} MB in scope), ${todo.length} still to copy.`);
  if (!APPLY) return;

  let done = 0;
  await mapLimit(todo, 4, async ({ f, target }) => {
    try {
      const [buf] = await f.download();
      const ext = f.name.split('.').pop()?.toLowerCase();
      let contentType = f.metadata?.contentType;
      if (!contentType || !contentType.startsWith('image/')) contentType = EXT_TYPES[ext] ?? 'image/jpeg';
      const { error } = await sb.storage.from(target.bucket).upload(target.path, buf, { contentType, upsert: true });
      if (error) { report.skip('storage', f.name, `upload failed: ${error.message}`); return; }
      const url = sb.storage.from(target.bucket).getPublicUrl(target.path).data.publicUrl;
      state.data.storage[f.name] = url;
      urlMap.set(f.name, url);
      done += 1;
      if (done % 25 === 0) { state.save(); console.log(`  copied ${done}/${todo.length}`); }
    } catch (e) {
      report.skip('storage', f.name, `copy failed: ${e.message}`);
    }
  });
  state.save();
  r.written = done;
  console.log(`Storage: copied ${done} object(s).`);
}

// ── Generic collection import ────────────────────────────────────────────────

function buildEntries(report, table, docs, transform, ctx, finish = (d, row) => row) {
  const entries = [];
  if (table) report.t(table).source = docs.length;
  for (const d of docs) {
    const t = transform(d.id, d.data, ctx);
    if (table) t.warnings.forEach((w) => report.warn(table, d.id, w));
    if (t.skip) { if (table) report.skip(table, d.id, t.skip); continue; }
    const row = finish(d, t.row);
    entries.push({ sourceId: d.id, row });
    if (table) { report.t(table).ready += 1; report.sample(table, row); }
  }
  return entries;
}

/**
 * strategy:
 *   'legacy'  upsert on legacy_firebase_id (no id sent)
 *   'state'   id from migration-state.json, upsert on id
 *   'natural' upsert on the table's natural unique key (no id sent)
 */
async function importCollection({ fb, sb, state, report, ctx, source, table, transform, strategy, upsert, key }) {
  const docs = await readCollection(fb.db, source);
  let entries = buildEntries(report, table, docs, transform, ctx,
    strategy === 'state' ? (d, row) => ({ id: state.idFor(table, d.id), ...row }) : undefined);
  if (key) entries = dedupe(report, table, entries, key);
  report.t(table).ready = entries.length;
  if (!APPLY) return entries;
  state.save();
  const options = upsert ?? { onConflict: strategy === 'legacy' ? 'legacy_firebase_id' : 'id' };
  report.t(table).written += await upsertEntries(sb, report, table, entries, options);
  return entries;
}

async function importAlerts({ fb, sb, state, report, ctx, touched }) {
  // The insert trigger only enqueues 'alert_created' for active alerts, and
  // alerts have no update trigger: write every alert inactive, then restore
  // is_active on the ones that were active in Firestore.
  const docs = await readCollection(fb.db, 'alerts');
  const entries = buildEntries(report, 'alerts', docs, transformAlert, ctx,
    (d, row) => ({ id: state.idFor('alerts', d.id), ...row }));
  if (!APPLY) return;
  state.save();
  entries.forEach((e) => touched.add(e.row.id));
  const inactive = entries.map((e) => ({ ...e, row: { ...e.row, is_active: false } }));
  report.t('alerts').written += await upsertEntries(sb, report, 'alerts', inactive, { onConflict: 'id' });
  const activeIds = entries.filter((e) => e.row.is_active).map((e) => e.row.id);
  for (let i = 0; i < activeIds.length; i += IN_CHUNK) {
    must(await sb.from('alerts').update({ is_active: true }).in('id', activeIds.slice(i, i + IN_CHUNK)), 'reactivate alerts');
  }
}

// ── Password resets ──────────────────────────────────────────────────────────

async function sendPasswordResets(sb, state, report, plans) {
  const r = report.t('password_resets');
  const throttle = Number(process.env.RESET_THROTTLE_MS ?? 2000);
  const redirectTo = process.env.PASSWORD_RESET_REDIRECT_URL || undefined;
  const targets = [];
  const seen = new Set();
  let phoneUsers = 0;
  for (const [uid, t] of plans) {
    if (t.skip || (APPLY && !state.data.users[uid])) continue;
    if (t.kind === 'phone') { phoneUsers += 1; continue; }
    if (t.row.profile.is_disabled) continue;
    const email = t.row.auth.email;
    if (isPhoneEmail(email)) { phoneUsers += 1; continue; }
    if (seen.has(email)) continue; // merged duplicate accounts share one email
    seen.add(email);
    r.source += 1;
    if (state.data.passwordResets[email]) continue;
    targets.push({ uid, email });
  }
  r.ready = targets.length;
  console.log(`\nPassword resets: ${r.source} email user(s), ${targets.length} not yet sent; ${phoneUsers} phone user(s) sign in with SMS OTP.`);
  if (!APPLY) { report.notes.push('Password resets are only sent with --apply.'); return; }

  for (const { uid, email } of targets) {
    const { error } = await sb.auth.resetPasswordForEmail(email, { redirectTo });
    if (error) {
      if (error.status === 429 || /rate limit/i.test(error.message)) {
        report.notes.push(`Password resets stopped by rate limit after ${r.written}; re-run with --send-password-resets to continue.`);
        break;
      }
      report.skip('password_resets', uid, `reset failed: ${error.message}`);
    } else {
      state.data.passwordResets[email] = new Date().toISOString();
      state.save();
      r.written += 1;
    }
    await sleep(throttle);
  }
  console.log(`Password reset emails sent: ${r.written}.`);
}

main().catch((e) => {
  console.error(`\nMigration failed: ${e.stack ?? e.message}`);
  process.exit(1);
});
