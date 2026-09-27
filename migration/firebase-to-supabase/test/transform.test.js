import { test, describe } from 'node:test';
import assert from 'node:assert/strict';

import {
  toIso, isUuid, asBool, asInt, refId, normalizeReportStatus, normalizeSeverity,
  normalizeAlertSeverity, normalizeRole, normalizeOverrideAction, isPhoneEmail,
  phoneFromFakeEmail, toE164, extractStoragePath, storageTargetFor, rewriteUrl, cleanImageUrl,
  transformUser, transformReport, transformVerification, transformVerificationOverride,
  transformAlert, transformMessage, transformContact, transformKnowledge, transformAuthority,
  transformTrustedDevice, transformLoginHistory, transformNdpaConsent, decodeHtmlEntities,
  capText, imageUrl, normalizeNigerianState, NIGERIAN_STATES, storageUploadPlan, STORAGE_MAX_BYTES,
  REPORT_TEXT_LIMITS, lgaPairs, canonicalLga, isAmbiguousLga, isAllLgas,
} from '../src/transform.js';
import { NIGERIA_LGAS_BY_STATE } from '../src/nigeria-lgas.js';

const NOW = '2026-09-25T00:00:00.000Z';
const users = { alice: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', bob: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' };
const reports = { r1: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc' };
const ctx = {
  now: NOW,
  user: (uid) => users[uid] ?? null,
  report: (id) => reports[id] ?? null,
  url: (u) => u,
  // alice is in Nasarawa, bob in Lagos (neither an 'Obi' state for bob).
  userState: (uid) => ({ alice: 'Nasarawa', bob: 'Lagos' })[uid] ?? null,
};
// A context with no creator-state resolver at all (older callers / dry runs).
const ctxNoStates = { ...ctx, userState: undefined };
const FB_URL =
  'https://firebasestorage.googleapis.com/v0/b/ewer-8f788.firebasestorage.app/o/report_images%2Falice%2F1700000000_0.jpg?alt=media&token=abc';

describe('timestamps', () => {
  test('Firestore Timestamp-like objects', () => {
    assert.equal(toIso({ toDate: () => new Date(Date.UTC(2025, 0, 2)) }), '2025-01-02T00:00:00.000Z');
    assert.equal(toIso({ _seconds: 1700000000, _nanoseconds: 500000000 }), '2023-11-14T22:13:20.500Z');
    assert.equal(toIso({ seconds: 1700000000, nanoseconds: 0 }), '2023-11-14T22:13:20.000Z');
  });
  test('ISO strings, Dates, epoch numbers', () => {
    assert.equal(toIso('2025-03-04T05:06:07.123456'), new Date('2025-03-04T05:06:07.123456').toISOString());
    assert.equal(toIso('2025-03-04T05:06:07Z'), '2025-03-04T05:06:07.000Z');
    assert.equal(toIso(new Date(0)), '1970-01-01T00:00:00.000Z');
    assert.equal(toIso(1700000000), '2023-11-14T22:13:20.000Z');
    assert.equal(toIso(1700000000000), '2023-11-14T22:13:20.000Z');
    assert.equal(toIso('1700000000000'), '2023-11-14T22:13:20.000Z');
  });
  test('missing or garbage → null', () => {
    for (const v of [null, undefined, '', 'not a date', {}, []]) assert.equal(toIso(v), null);
  });
});

describe('scalars', () => {
  test('isUuid', () => {
    assert.ok(isUuid(users.alice));
    assert.ok(!isUuid('Xk3jf8s9dK2mQpL0aB1c'));
    assert.ok(!isUuid(null));
  });
  test('asBool / asInt / refId', () => {
    assert.equal(asBool('true'), true);
    assert.equal(asBool(undefined, true), true);
    assert.equal(asInt('3.7'), 3);
    assert.equal(asInt('x', 5), 5);
    assert.equal(refId('users/alice'), 'alice');
    assert.equal(refId({ id: 'bob', path: 'users/bob' }), 'bob');
    assert.equal(refId(''), null);
  });
});

describe('status and severity normalisation', () => {
  test('legacy report statuses', () => {
    assert.deepEqual(normalizeReportStatus('acknowledged'), { status: 'verified', escalated: false, known: true });
    assert.deepEqual(normalizeReportStatus('validated'), { status: 'approved', escalated: false, known: true });
    assert.deepEqual(normalizeReportStatus('resolved'), { status: 'approved', escalated: false, known: true });
    assert.deepEqual(normalizeReportStatus('escalated'), { status: 'pending', escalated: true, known: true });
    assert.deepEqual(normalizeReportStatus('Rejected'), { status: 'rejected', escalated: false, known: true });
    assert.deepEqual(normalizeReportStatus('pending', true), { status: 'pending', escalated: true, known: true });
    assert.equal(normalizeReportStatus('weird').known, false);
    assert.equal(normalizeReportStatus('weird').status, 'pending');
  });
  test('report severities', () => {
    assert.equal(normalizeSeverity('High Severity'), 'high');
    assert.equal(normalizeSeverity('HIGH'), 'high');
    assert.equal(normalizeSeverity('Low severity'), 'low');
    assert.equal(normalizeSeverity('moderate'), 'medium');
    assert.equal(normalizeSeverity('Severe'), 'critical');
    assert.equal(normalizeSeverity('extreme'), 'critical');
    assert.equal(normalizeSeverity('CRITICAL'), 'critical');
    assert.equal(normalizeSeverity('banana'), null);
    assert.equal(normalizeSeverity(null), null);
  });
  test('alert severities', () => {
    assert.equal(normalizeAlertSeverity('warning'), 'warning');
    assert.equal(normalizeAlertSeverity('HIGH'), 'warning');
    assert.equal(normalizeAlertSeverity('critical'), 'critical');
    assert.equal(normalizeAlertSeverity('low'), 'info');
    assert.equal(normalizeAlertSeverity('?'), null);
  });
  test('roles and override actions', () => {
    assert.equal(normalizeRole('EWM'), 'ewm');
    assert.equal(normalizeRole('techsupport'), 'techSupport');
    assert.equal(normalizeRole('tech_support'), 'techSupport');
    assert.equal(normalizeRole('LDP Coordinator'), 'ldp_coordinator');
    assert.equal(normalizeRole('project_staff'), 'project_staff');
    assert.equal(normalizeRole('superuser'), null);
    assert.equal(normalizeOverrideAction('approve'), 'approved');
    assert.equal(normalizeOverrideAction('rejected'), 'rejected');
    assert.equal(normalizeOverrideAction('maybe'), null);
  });
});

describe('phone accounts', () => {
  test('fake @ewer.phone emails', () => {
    assert.ok(isPhoneEmail('2348012345678@ewer.phone'));
    assert.ok(isPhoneEmail('2348012345678@EWER.PHONE'));
    assert.ok(!isPhoneEmail('someone@example.com'));
    assert.ok(!isPhoneEmail('abc@ewer.phone'));
    assert.equal(phoneFromFakeEmail('2348012345678@ewer.phone'), '+2348012345678');
    assert.equal(phoneFromFakeEmail('a@b.c'), null);
  });
  test('toE164', () => {
    assert.equal(toE164('+234 801 234 5678'), '+2348012345678');
    assert.equal(toE164('08012345678'), '+2348012345678');
    assert.equal(toE164('abc'), null);
  });
});

describe('storage URLs', () => {
  test('extract decoded object path from Firebase download URLs', () => {
    assert.deepEqual(extractStoragePath(FB_URL), {
      bucket: 'ewer-8f788.firebasestorage.app',
      path: 'report_images/alice/1700000000_0.jpg',
    });
    assert.deepEqual(extractStoragePath('https://firebasestorage.googleapis.com/v0/b/ewer-8f788.appspot.com/o/profile_images%2Fbob%2Fprofile%20pic.png?alt=media'), {
      bucket: 'ewer-8f788.appspot.com',
      path: 'profile_images/bob/profile pic.png',
    });
    assert.deepEqual(extractStoragePath('gs://ewer-8f788.appspot.com/report_images/alice/x.jpg'), {
      bucket: 'ewer-8f788.appspot.com',
      path: 'report_images/alice/x.jpg',
    });
    assert.deepEqual(extractStoragePath('https://storage.googleapis.com/ewer-8f788.appspot.com/report_images/alice/y.jpg'), {
      bucket: 'ewer-8f788.appspot.com',
      path: 'report_images/alice/y.jpg',
    });
  });
  test('non-Firebase values → null', () => {
    assert.equal(extractStoragePath('/data/user/0/app/cache/img.jpg'), null);
    assert.equal(extractStoragePath('https://xyz.supabase.co/storage/v1/object/public/report-images/a.jpg'), null);
    assert.equal(extractStoragePath(''), null);
    assert.equal(extractStoragePath(undefined), null);
  });
  test('storage target and URL rewrite', () => {
    assert.deepEqual(storageTargetFor('report_images/alice/1.jpg', ctx.user), {
      bucket: 'report-images', path: `${users.alice}/1.jpg`, uid: 'alice',
    });
    assert.deepEqual(storageTargetFor('profile_images/bob/p.png', ctx.user), {
      bucket: 'profile-images', path: `${users.bob}/p.png`, uid: 'bob',
    });
    assert.equal(storageTargetFor('report_images/ghost/1.jpg', ctx.user), null);
    assert.equal(storageTargetFor('other/alice/1.jpg', ctx.user), null);
    const map = new Map([['report_images/alice/1700000000_0.jpg', 'https://new/url.jpg']]);
    assert.equal(rewriteUrl(FB_URL, map), 'https://new/url.jpg');
    assert.equal(rewriteUrl('https://elsewhere/x.jpg', map), 'https://elsewhere/x.jpg');
    assert.equal(cleanImageUrl('/local/path.jpg'), '');
    assert.equal(cleanImageUrl('https://a/b.jpg'), 'https://a/b.jpg');
  });
});

describe('users', () => {
  const authEmail = {
    uid: 'alice', email: 'Alice@Example.com', emailVerified: false, disabled: false,
    metadata: { creationTime: 'Tue, 14 Nov 2023 22:13:20 GMT', lastSignInTime: 'Wed, 15 Nov 2023 10:00:00 GMT' },
  };
  test('email user maps auth params and profile patch', () => {
    const doc = {
      name: 'Alice', role: 'ewm', state: 'Benue', lga: 'Makurdi', ward: 'Ward 1', phone: '+2348000000000',
      isVerified: true, isApproved: true, isDisabled: true, biometricsEnabled: true, monitoringZone: 'Z1',
      profileImageUrl: FB_URL, registrationCode: 'REG-1', createdAt: '2023-11-01T00:00:00.000',
      lastLoginAt: '2024-01-01T12:00:00.000Z', fcmToken: 'x',
    };
    const t = transformUser('alice', authEmail, doc, ctx);
    assert.equal(t.skip, null);
    assert.equal(t.kind, 'email');
    assert.equal(t.row.auth.email, 'alice@example.com');
    assert.equal(t.row.auth.email_confirm, true, 'isVerified confirms the email');
    assert.deepEqual(t.row.auth.user_metadata, {
      name: 'Alice', role: 'ewm', state: 'Benue', lga: 'Makurdi', ward: 'Ward 1', phone: '+2348000000000', address: '',
    });
    const p = t.row.profile;
    assert.equal(p.role, 'ewm');
    assert.equal(p.is_approved, true);
    assert.equal(p.is_disabled, true);
    assert.equal(p.is_verified, true);
    assert.equal(p.biometrics_enabled, true);
    assert.equal(p.monitoring_zone, 'Z1');
    assert.equal(p.profile_image_url, FB_URL);
    assert.equal(p.registration_code, 'REG-1');
    assert.equal(p.last_login_at, '2024-01-01T12:00:00.000Z');
    assert.equal(p.legacy_firebase_uid, 'alice');
    assert.ok(p.created_at);
    assert.ok(!('fcm_token' in p));
  });
  test('phone user uses +digits and phone_confirm', () => {
    const t = transformUser('bob', { uid: 'bob', email: '2348012345678@ewer.phone', emailVerified: false }, { name: 'Bob', role: 'user' }, ctx);
    assert.equal(t.kind, 'phone');
    assert.equal(t.row.auth.phone, '+2348012345678');
    assert.equal(t.row.auth.phone_confirm, true);
    assert.ok(!('email' in t.row.auth));
    assert.equal(t.row.profile.phone, '+2348012345678');
  });
  test('email_confirm false when neither auth nor doc verified; unknown role → user', () => {
    const t = transformUser('alice', authEmail, { role: 'superuser' }, ctx);
    assert.equal(t.row.auth.email_confirm, false);
    assert.equal(t.row.profile.role, 'user');
    assert.ok(t.warnings.some((w) => w.includes('unknown role')));
  });
  test('approved but unverified account is imported confirmed (DB only approves confirmed accounts)', () => {
    const t = transformUser('erin', authEmail, { role: 'ewm', isApproved: true }, ctx);
    assert.equal(t.row.auth.email_confirm, true);
    assert.equal(t.row.profile.is_approved, true);
    assert.ok(t.warnings.some((w) => w.includes('imported as confirmed')));
  });
  test('Firestore-only user and auth-only user', () => {
    const docOnly = transformUser('carol', null, { email: 'carol@example.com', name: 'Carol' }, ctx);
    assert.equal(docOnly.kind, 'email');
    assert.ok(docOnly.warnings.some((w) => w.includes('no Firebase Auth record')));
    const authOnly = transformUser('dave', { uid: 'dave', email: 'dave@example.com', emailVerified: true }, null, ctx);
    assert.equal(authOnly.row.auth.email_confirm, true);
    assert.equal(authOnly.row.profile.name, 'User');
  });
  test('no email or phone → skipped', () => {
    assert.ok(transformUser('anon', { uid: 'anon' }, null, ctx).skip);
  });
  test('native phone-auth user', () => {
    const t = transformUser('pp', { uid: 'pp', phoneNumber: '+2348099999999' }, null, ctx);
    assert.equal(t.kind, 'phone');
    assert.equal(t.row.auth.phone, '+2348099999999');
  });
});

describe('reports', () => {
  const doc = {
    userId: 'alice', hazardType: 'flood', severity: 'High Severity', latitude: 7.7, longitude: '8.5',
    locationDetails: 'Near market', ward: 'Ward 1', lga: 'Makurdi', state: 'Benue', description: 'Water rising',
    submittedAt: '2025-06-01T10:00:00.000', imageUrls: [FB_URL, '/local/cache.jpg'], status: 'escalated',
    verificationCount: 3, createdAt: { _seconds: 1748772000, _nanoseconds: 0 },
    escalationScheduledAt: '2025-06-01T10:30:00.000Z', escalationStatus: 'pending',
  };
  test('maps fields and normalises status/severity', () => {
    const { row, skip, warnings } = transformReport('fsId123', doc, { ...ctx, url: (u) => u.replace('firebasestorage', 'NEW') });
    assert.equal(skip, null);
    assert.deepEqual(warnings, []);
    assert.equal(row.user_id, users.alice);
    assert.equal(row.severity, 'high');
    assert.equal(row.is_alert, true);
    assert.equal(row.status, 'pending');
    assert.equal(row.escalated, true);
    assert.equal(row.longitude, 8.5);
    assert.equal(row.location_details, 'Near market');
    assert.equal(row.location, 'Near market');
    assert.equal(row.verification_count, 3);
    assert.equal(row.legacy_firebase_id, 'fsId123');
    assert.equal(row.image_urls.length, 1);
    assert.ok(row.image_urls[0].includes('NEW'));
    assert.equal(row.escalation_scheduled_at, '2025-06-01T10:30:00.000Z');
    assert.equal(row.created_at, '2025-06-01T10:00:00.000Z');
  });
  test('unknown reporter, severity and missing lga produce warnings, not skips', () => {
    const { row, skip, warnings } = transformReport('x', { userId: 'ghost', severity: '??', hazardType: 'fire' }, ctx);
    assert.equal(skip, null);
    assert.equal(row.user_id, null);
    assert.equal(row.severity, 'medium');
    assert.equal(row.lga, 'Unknown');
    assert.equal(row.submitted_at, NOW);
    assert.equal(warnings.length, 4);
  });
  test('legacy statuses map through', () => {
    assert.equal(transformReport('a', { ...doc, status: 'validated' }, ctx).row.status, 'approved');
    assert.equal(transformReport('a', { ...doc, status: 'acknowledged' }, ctx).row.status, 'verified');
    assert.equal(transformReport('a', { ...doc, status: 'resolved' }, ctx).row.status, 'approved');
  });
});

describe('other collections', () => {
  test('verifications', () => {
    const { row } = transformVerification('v1', { reportId: 'r1', verifierId: 'bob', isConfirmed: true, comment: 'yes', submittedAt: { _seconds: 1700000000 } }, ctx);
    assert.deepEqual(row, {
      report_id: reports.r1, verifier_id: users.bob, is_confirmed: true, comment: 'yes',
      submitted_at: '2023-11-14T22:13:20.000Z', created_at: '2023-11-14T22:13:20.000Z',
    });
    assert.match(transformVerification('v2', { reportId: 'nope', verifierId: 'bob' }, ctx).skip, /report nope/);
    assert.match(transformVerification('v3', { reportId: 'r1', userId: 'ghost' }, ctx).skip, /verifier ghost/);
  });
  test('verification overrides', () => {
    const { row } = transformVerificationOverride('o1', { reportId: 'r1', validatorId: 'alice', action: 'rejected', reason: 'dup', timestamp: { _seconds: 1700000000 } }, ctx);
    assert.equal(row.action, 'rejected');
    assert.equal(row.validator_id, users.alice);
    assert.equal(row.created_at, '2023-11-14T22:13:20.000Z');
    assert.ok(transformVerificationOverride('o2', { reportId: 'r1', validatorId: 'alice', action: '?' }, ctx).skip);
  });
  test('alerts: targetLga, createdBy admin → null', () => {
    const { row } = transformAlert('a1', { title: 'Flood', message: 'Move', severity: 'warning', targetLga: 'Makurdi', createdBy: 'admin', isActive: true }, ctx);
    assert.equal(row.target_lga, 'Makurdi');
    assert.equal(row.created_by, null);
    assert.equal(row.is_active, true);
    assert.equal(transformAlert('a2', { title: 'x', createdBy: 'alice' }, ctx).row.created_by, users.alice);
    assert.equal(transformAlert('a3', { title: 'x' }, ctx).row.target_lga, 'All');
    assert.ok(transformAlert('a4', { message: 'no title' }, ctx).skip);
  });
  test('messages (ISO sentAt)', () => {
    const { row } = transformMessage('m1', { chatId: 'general', senderId: 'alice', senderName: 'Alice', message: 'hi', sentAt: '2025-01-01T00:00:00.000Z' }, ctx);
    assert.equal(row.sent_at, '2025-01-01T00:00:00.000Z');
    assert.equal(row.sender_id, users.alice);
    assert.ok(transformMessage('m2', { senderId: 'ghost', message: 'x' }, ctx).skip);
  });
  test('contacts', () => {
    const { row } = transformContact('c1', { userId: 'alice', name: 'Mum', relationship: 'mother', phone: '0801' }, ctx);
    assert.equal(row.role, 'mother');
    assert.equal(row.category, 'other');
    assert.equal(row.is_available, true);
    assert.ok(transformContact('c2', { userId: 'alice', name: 'x' }, ctx).skip);
  });
  test('knowledge base and authorities', () => {
    const kb = transformKnowledge('k1', { title: 'Floods', content: 'c', hazardType: 'flood', imageUrl: 'https://img' }, ctx).row;
    assert.equal(kb.legacy_firebase_id, 'k1');
    assert.equal(kb.category, 'General');
    assert.equal(transformAuthority('au1', { name: 'SEMA', phone: '+234', coverageLGA: 'Makurdi' }, ctx).row.coverage_lga, 'Makurdi');
    assert.equal(transformAuthority('au2', { phone: '+234', lga: 'Gboko' }, ctx).row.coverage_lga, 'Gboko');
    assert.ok(transformAuthority('au3', { phone: '+234' }, ctx).skip);
    assert.equal(transformAuthority('au4', { phone: '+234', lga: 'Obi', state: 'Benue State' }, ctx).row.coverage_state, 'Benue');
    // An unambiguous LGA name fixes its own state: Makurdi is only in Benue.
    assert.equal(transformAuthority('au5', { phone: '+234', lga: 'Makurdi' }, ctx).row.coverage_state, 'Benue');
  });

  test('authorities: coverage_state is always resolved, never guessed', () => {
    // 1. Unambiguous LGA, no state: the one state it can be, both names
    //    re-spelled canonically. Nothing about who is texted changes.
    const only = transformAuthority('a1', { name: 'Gboko Desk', phone: '+2348030000001', lga: '  gBOKO ' }, ctx);
    assert.equal(only.skip, null);
    assert.deepEqual(only.warnings, []);
    assert.equal(only.row.coverage_state, 'Benue');
    assert.equal(only.row.coverage_lga, 'Gboko');

    // 2. State given: the pair is validated and canonicalised.
    const pair = transformAuthority('a2', { name: 'Obi Desk', phone: '+2348030000002', lga: 'obi', coverageState: 'nasarawa state' }, ctx);
    assert.equal(pair.skip, null);
    assert.deepEqual(pair.warnings, []);
    assert.equal(pair.row.coverage_state, 'Nasarawa');
    assert.equal(pair.row.coverage_lga, 'Obi');

    // 3. Ambiguous LGA, no state: SKIPPED, naming the contact, its phone and
    //    the candidate states. Picking one would text the wrong desk.
    for (const [lga, states] of [
      ['Bassa', 'Kogi, Plateau'], ['Ifelodun', 'Kwara, Osun'], ['Irepodun', 'Kwara, Osun'],
      ['Nasarawa', 'Kano, Nasarawa'], ['Obi', 'Benue, Nasarawa'], ['Surulere', 'Lagos, Oyo'],
    ]) {
      const amb = transformAuthority('a3', { name: `${lga} Desk`, phone: '+2348030000003', lga }, ctx);
      assert.equal(amb.row, undefined, lga);
      assert.match(amb.skip, new RegExp(`authority '${lga} Desk' \\(\\+2348030000003\\)`), lga);
      assert.ok(amb.skip.includes(`exists in more than one state (${states})`), `${lga}: ${amb.skip}`);
      assert.match(amb.skip, /Authorities page/, lga);
    }

    // 4. A state/LGA pair that does not exist: SKIPPED, naming the real states.
    const wrong = transformAuthority('a4', { name: 'Wrong', phone: '+2348030000004', lga: 'Obi', state: 'Plateau' }, ctx);
    assert.equal(wrong.row, undefined);
    assert.match(wrong.skip, /'Obi' is not an LGA of Plateau \(it is in Benue, Nasarawa\)/);

    // 5. An LGA that is in no state at all: SKIPPED.
    const ghost = transformAuthority('a5', { name: 'Ghost', phone: '+2348030000005', lga: 'Atlantis City' }, ctx);
    assert.equal(ghost.row, undefined);
    assert.match(ghost.skip, /is not an LGA of any Nigerian state/);

    // 6. An unrecognised state: SKIPPED (it used to become coverage_state null,
    //    which the database now rejects).
    const bad = transformAuthority('a6', { name: 'Bad', phone: '+2348030000006', lga: 'Makurdi', state: 'Middle Belt' }, ctx);
    assert.equal(bad.row, undefined);
    assert.match(bad.skip, /state 'Middle Belt' is not a Nigerian state/);

    // No authority this module emits can violate the constraint.
    for (const d of [
      { phone: '+234', lga: 'Makurdi' }, { phone: '+234', lga: 'Obi', state: 'Benue' },
      { phone: '+234', lga: 'obi', coverageState: 'BENUE STATE' }, { phone: '+234', lga: "Qua'an Pan" },
    ]) {
      const r = transformAuthority('x', d, ctx);
      assert.equal(r.skip, null, JSON.stringify(d));
      assert.ok(r.row.coverage_state, JSON.stringify(d));
      assert.deepEqual(canonicalLga(r.row.coverage_state, r.row.coverage_lga), r.row.coverage_lga, JSON.stringify(d));
    }
  });
  test('trusted devices and login history (timestamp → occurred_at)', () => {
    const td = transformTrustedDevice('t1', { userId: 'alice', deviceFingerprint: 'fp', deviceName: 'Pixel', lastUsed: { _seconds: 1700000000 } }, ctx).row;
    assert.equal(td.last_used, '2023-11-14T22:13:20.000Z');
    const lh = transformLoginHistory('l1', { userId: 'bob', success: true, timestamp: { _seconds: 1700000000 }, riskScore: 20 }, ctx).row;
    assert.equal(lh.occurred_at, '2023-11-14T22:13:20.000Z');
    assert.equal(lh.risk_score, 20);
  });
  test('ndpa consents (uid → user_id, falls back to doc id)', () => {
    const c = transformNdpaConsent('alice', { uid: 'alice', consentedAt: { _seconds: 1700000000 }, policyVersion: '1.0', dataResidency: 'us-central1', method: 'registration_screen' }, ctx).row;
    assert.equal(c.user_id, users.alice);
    assert.equal(c.policy_version, '1.0');
    assert.equal(transformNdpaConsent('bob', {}, ctx).row.user_id, users.bob);
    assert.ok(transformNdpaConsent('ghost', {}, ctx).skip);
  });
});

describe('legacy HTML-escaped free text', () => {
  test('decodeHtmlEntities decodes the entities old builds produced, once', () => {
    assert.equal(decodeHtmlEntities('don&#x27;t'), "don't");
    assert.equal(decodeHtmlEntities('O&#39;Brien &amp; sons'), "O'Brien & sons");
    assert.equal(decodeHtmlEntities('&lt;b&gt; &quot;x&quot; 1&#x2F;2'), '<b> "x" 1/2');
    assert.equal(decodeHtmlEntities('A&#x2f;B'), 'A/B');
    // Single pass: a literally typed "&lt;" (escaped to "&amp;lt;") survives.
    assert.equal(decodeHtmlEntities('&amp;lt;'), '&lt;');
    // Unknown entities / bare ampersands are left alone.
    assert.equal(decodeHtmlEntities('R&D &nbsp; &copy;'), 'R&D &nbsp; &copy;');
    assert.equal(decodeHtmlEntities('plain'), 'plain');
    assert.equal(decodeHtmlEntities(undefined), undefined);
  });

  test('report free-text fields are decoded', () => {
    const { row } = transformReport('x', {
      userId: 'alice', severity: 'high', lga: 'Jos North',
      description: 'Water didn&#x27;t recede &amp; roads &lt;closed&gt;',
      locationDetails: 'Behind &quot;Main&quot; market',
      address: 'No 5&#x2F;7 Street',
      rejectionReason: 'isn&#x27;t valid',
    }, ctx);
    assert.equal(row.description, "Water didn't recede & roads <closed>");
    assert.equal(row.location_details, 'Behind "Main" market');
    assert.equal(row.location, 'Behind "Main" market');
    assert.equal(row.address, 'No 5/7 Street');
    assert.equal(row.rejection_reason, "isn't valid");
  });

  test('user name/address, messages and contacts are decoded', () => {
    const user = transformUser('u1', { email: 'a@b.co' }, { name: 'Ngozi O&#x27;Neil', address: '12 A&amp;B Road' }, ctx);
    assert.equal(user.row.profile.name, "Ngozi O'Neil");
    assert.equal(user.row.profile.address, '12 A&B Road');
    assert.equal(user.row.auth.user_metadata.name, "Ngozi O'Neil");

    const msg = transformMessage('m', { senderId: 'alice', text: 'We&#x27;re safe', senderName: 'A&amp;B' }, ctx);
    assert.equal(msg.row.message, "We're safe");
    assert.equal(msg.row.sender_name, 'A&B');

    const contact = transformContact('c', { userId: 'alice', phone: '0803', name: 'Mama&#x27;s', organization: 'Red &quot;Cross&quot;' }, ctx);
    assert.equal(contact.row.name, "Mama's");
    assert.equal(contact.row.organization, 'Red "Cross"');
  });
});

describe('audit fixes', () => {
  const GS = 'gs://ewer-8f788.appspot.com/report_images/alice/x.jpg';
  const copied = new Map([['report_images/alice/x.jpg', 'https://sb.example/storage/v1/object/public/report-images/u/x.jpg']]);
  const ctxCopied = { ...ctx, url: (u) => rewriteUrl(u, copied) };

  test('report text fields are cut to the check-constraint limits, with warnings', () => {
    const long = (n, ch = 'x') => ch.repeat(n);
    const { row, warnings } = transformReport('big', {
      userId: 'alice', severity: 'high', hazardType: long(80), description: long(2500), locationDetails: long(600),
      address: long(501), ward: long(121), lga: long(200), state: long(130),
      imageUrls: Array.from({ length: 12 }, (_, i) => `https://img/${i}.jpg`),
    }, ctx);
    for (const [field, max] of Object.entries(REPORT_TEXT_LIMITS)) {
      assert.ok(Array.from(row[field]).length <= max, `${field} ≤ ${max}`);
    }
    assert.equal(row.hazard_type.length, 60);
    assert.equal(row.description.length, 2000);
    assert.equal(row.location.length, 500);
    assert.equal(row.image_urls.length, 10);
    assert.deepEqual(row.image_urls.slice(-1), ['https://img/9.jpg']);
    for (const f of ['hazard_type', 'description', 'location_details', 'location', 'address', 'ward', 'lga', 'state']) {
      assert.ok(warnings.some((w) => w.startsWith(`${f} truncated`)), `warning for ${f}`);
    }
    assert.ok(warnings.some((w) => w.includes('12 images; only the first 10 kept')));
    // Within limits: no truncation warnings.
    assert.deepEqual(transformReport('ok', { userId: 'alice', severity: 'high', lga: 'Makurdi', hazardType: 'flood', submittedAt: NOW }, ctx).warnings, []);
  });

  test('capText counts code points like char_length', () => {
    const w = [];
    assert.equal(capText('😀'.repeat(3), 3, 'f', w), '😀😀😀');
    assert.deepEqual(w, []);
    assert.equal(capText('😀'.repeat(4), 3, 'f', w), '😀😀😀');
    assert.deepEqual(w, ['f truncated from 4 to 3 characters']);
  });

  test('message text is cut to 2000 characters with a warning', () => {
    const t = transformMessage('m', { senderId: 'alice', message: 'y'.repeat(2100) }, ctx);
    assert.equal(t.row.message.length, 2000);
    assert.deepEqual(t.warnings, ['message truncated from 2100 to 2000 characters']);
    assert.deepEqual(transformMessage('m2', { senderId: 'alice', message: 'short' }, ctx).warnings, []);
  });

  test('gs:// image references are rewritten before filtering to http(s)', () => {
    assert.equal(imageUrl(GS, ctxCopied), copied.get('report_images/alice/x.jpg'));
    const w = [];
    assert.equal(imageUrl('gs://ewer-8f788.appspot.com/report_images/alice/other.jpg', ctxCopied, w), '');
    assert.equal(w.length, 1);
    assert.equal(imageUrl('/data/local.jpg', ctxCopied, w), '');
    assert.equal(w.length, 1, 'local paths are dropped silently');

    const rep = transformReport('r', { userId: 'alice', severity: 'low', lga: 'X', imageUrls: [GS, '/tmp/a.jpg'] }, ctxCopied);
    assert.deepEqual(rep.row.image_urls, [copied.get('report_images/alice/x.jpg')]);
    const user = transformUser('alice', { uid: 'alice', email: 'a@b.co' }, { profileImageUrl: GS }, ctxCopied);
    assert.equal(user.row.profile.profile_image_url, copied.get('report_images/alice/x.jpg'));
    const kb = transformKnowledge('k', { title: 'Local guide', imageUrl: GS }, ctxCopied);
    assert.equal(kb.row.image_url, copied.get('report_images/alice/x.jpg'));
    assert.equal(transformKnowledge('k2', { title: 'Local guide', imageUrl: 'gs://b/other.png' }, ctxCopied).row.image_url, null);
  });

  test('coverage_state is mapped to the canonical state names', () => {
    assert.equal(NIGERIAN_STATES.length, 37);
    const cases = {
      benue: 'Benue', 'BENUE STATE': 'Benue', 'Nassarawa': 'Nasarawa', 'nasarawa state': 'Nasarawa',
      'Federal Capital Territory': 'FCT', Abuja: 'FCT', fct: 'FCT', 'FCT-Abuja': 'FCT', 'akwa-ibom': 'Akwa Ibom',
      'Cross Rivers': 'Cross River', ' plateau ': 'Plateau', Rivers: 'Rivers', Niger: 'Niger',
    };
    for (const [raw, want] of Object.entries(cases)) assert.equal(normalizeNigerianState(raw), want, raw);
    for (const s of NIGERIAN_STATES) assert.equal(normalizeNigerianState(s.toUpperCase()), s);
    assert.equal(normalizeNigerianState('Atlantis'), null);
    assert.equal(normalizeNigerianState(''), null);

    const t = transformAuthority('au', { phone: '+234', lga: 'Lafia', coverageState: 'NASSARAWA' }, ctx);
    assert.equal(t.row.coverage_state, 'Nasarawa');
    assert.deepEqual(t.warnings, []);
    // An unrecognised state is no longer turned into coverage_state null:
    // since 20260927090000 the column is NOT NULL, so the row is skipped.
    const bad = transformAuthority('au2', { phone: '+234', lga: 'Makurdi', state: 'Middle Belt' }, ctx);
    assert.equal(bad.row, undefined);
    assert.match(bad.skip, /state 'Middle Belt' is not a Nigerian state/);
  });

  test('verification overrides: action verified; unmigrated validator kept as null', () => {
    assert.equal(normalizeOverrideAction('verified'), 'verified');
    assert.equal(normalizeOverrideAction('Verify'), 'verified');
    const v = transformVerificationOverride('o', { reportId: 'r1', validatorId: 'alice', action: 'verified' }, ctx);
    assert.equal(v.row.action, 'verified');
    const ghost = transformVerificationOverride('o2', { reportId: 'r1', validatorId: 'ghost', action: 'approve' }, ctx);
    assert.equal(ghost.skip, null);
    assert.equal(ghost.row.validator_id, null);
    assert.deepEqual(ghost.warnings, ['validator ghost not migrated; validator_id set to null']);
    const none = transformVerificationOverride('o3', { reportId: 'r1', action: 'rejected' }, ctx);
    assert.equal(none.row.validator_id, null);
    assert.equal(none.warnings.length, 1);
  });

  test('storage upload plan: jpg alias, extension inference, disallowed types and size limit', () => {
    assert.deepEqual(storageUploadPlan('report_images/a/1.jpg', { contentType: 'image/jpg', size: '100' }), { contentType: 'image/jpeg' });
    assert.deepEqual(storageUploadPlan('report_images/a/1.PNG', { contentType: 'application/octet-stream' }), { contentType: 'image/png' });
    assert.deepEqual(storageUploadPlan('report_images/a/1.heic', {}), { contentType: 'image/heic' });
    assert.deepEqual(storageUploadPlan('report_images/a/1.webp', { contentType: 'image/webp; charset=binary' }), { contentType: 'image/webp' });
    assert.match(storageUploadPlan('report_images/a/1.gif', { contentType: 'image/gif' }).skip, /image\/gif not allowed/);
    assert.match(storageUploadPlan('report_images/a/clip.mp4', { contentType: 'video/mp4' }).skip, /video\/mp4 not allowed/);
    assert.match(storageUploadPlan('report_images/a/noext', {}).skip, /\(missing\) and extension \(none\) not allowed/);
    assert.match(storageUploadPlan('report_images/a/doc.pdf', { contentType: 'application/octet-stream' }).skip, /'\.pdf' not allowed/);
    assert.match(storageUploadPlan('report_images/a/big.jpg', { contentType: 'image/jpeg', size: STORAGE_MAX_BYTES + 1 }).skip, /larger than the 5 MB bucket limit/);
    assert.deepEqual(storageUploadPlan('report_images/a/edge.jpg', { contentType: 'image/jpeg', size: STORAGE_MAX_BYTES }), { contentType: 'image/jpeg' });
  });
});

// alerts.target_state is NOT NULL-in-effect since 20260927080000: the database
// rejects a target_lga that names an LGA without the state it is in. Every row
// transformAlert produces has to be resolvable to exactly one place.
describe('alert targets (state is mandatory)', () => {
  test('an LGA in exactly one state resolves to it, spelled canonically', () => {
    const { row, warnings } = transformAlert('a', { title: 'Flood', targetLga: 'Makurdi' }, ctx);
    assert.equal(row.target_lga, 'Makurdi');
    assert.equal(row.target_state, 'Benue');
    assert.deepEqual(warnings, []);
    // Case and padding in the source document are normalised to the canonical
    // spelling the database's foreign key requires.
    const messy = transformAlert('b', { title: 'Flood', targetLga: '  gWeR eAsT ' }, ctx).row;
    assert.equal(messy.target_lga, 'Gwer East');
    assert.equal(messy.target_state, 'Benue');
  });

  test("an ambiguous LGA uses the creator's profile state as a tiebreak", () => {
    const { row, warnings } = transformAlert('a', { title: 'Obi flood', targetLga: 'Obi', createdBy: 'alice' }, ctx);
    assert.equal(row.target_lga, 'Obi');
    assert.equal(row.target_state, 'Nasarawa');
    assert.match(warnings[0], /exists in Benue and Nasarawa/);
    assert.match(warnings[0], /resolved to Nasarawa from the alert creator's profile state/);
  });

  test('an ambiguous LGA with no usable tiebreak is skipped, naming the alert and why', () => {
    // No creator at all.
    const none = transformAlert('a', { title: 'Obi flood' , targetLga: 'Obi' }, ctx);
    assert.equal(none.row, undefined);
    assert.match(none.skip, /^alert 'Obi flood': /);
    assert.match(none.skip, /exists in more than one state \(Benue, Nasarawa\)/);
    assert.match(none.skip, /no creator whose profile state could disambiguate it/);

    // A creator whose own state is not one of the candidates.
    const wrong = transformAlert('b', { title: 'Obi flood', targetLga: 'Obi', createdBy: 'bob' }, ctx);
    assert.equal(wrong.row, undefined);
    assert.match(wrong.skip, /creator's profile state \(Lagos\) is not one of them/);

    // A context that cannot resolve creator states at all.
    const noResolver = transformAlert('c', { title: 'Obi flood', targetLga: 'Obi', createdBy: 'alice' }, ctxNoStates);
    assert.equal(noResolver.row, undefined);
    assert.match(noResolver.skip, /exists in more than one state/);

    // Never widened to 'All' or to a whole state to make it fit.
    for (const r of [none, wrong, noResolver]) assert.equal(r.row, undefined);
  });

  test('an LGA that is in no state is skipped', () => {
    const r = transformAlert('a', { title: 'Nowhere', targetLga: 'Atlantis Central', createdBy: 'alice' }, ctx);
    assert.equal(r.row, undefined);
    assert.match(r.skip, /^alert 'Nowhere': target LGA 'Atlantis Central' is not an LGA of any Nigerian state/);
  });

  test("target_lga 'All' keeps a null state, or the alert's own state", () => {
    assert.deepEqual(
      (() => { const { target_lga, target_state } = transformAlert('a', { title: 'x' }, ctx).row; return { target_lga, target_state }; })(),
      { target_lga: 'All', target_state: null },
    );
    // Explicit 'all'/'ALL'/blank all mean the same sentinel.
    for (const v of ['All', 'all', ' ALL ', '']) {
      const row = transformAlert('b', { title: 'x', targetLga: v }, ctx).row;
      assert.deepEqual([row.target_lga, row.target_state], ['All', null], `targetLga ${JSON.stringify(v)}`);
    }
    // 'All' with a state = every LGA of that state; the state is canonicalised.
    const statewide = transformAlert('c', { title: 'x', targetLga: 'All', targetState: 'nassarawa state' }, ctx).row;
    assert.deepEqual([statewide.target_lga, statewide.target_state], ['All', 'Nasarawa']);
  });

  test('a state on the document is used, and an impossible pair is skipped', () => {
    const ok = transformAlert('a', { title: 'x', targetLga: 'obi', targetState: 'benue state' }, ctx).row;
    assert.deepEqual([ok.target_lga, ok.target_state], ['Obi', 'Benue']);
    const mismatch = transformAlert('b', { title: 'x', targetLga: 'Obi', targetState: 'Plateau' }, ctx);
    assert.equal(mismatch.row, undefined);
    assert.match(mismatch.skip, /is not an LGA of Plateau \(it is in Benue, Nasarawa\)/);
    const unknownState = transformAlert('c', { title: 'x', targetLga: 'Obi', targetState: 'Atlantis' }, ctx);
    assert.equal(unknownState.row, undefined);
    assert.match(unknownState.skip, /target state 'Atlantis' is not a Nigerian state/);
  });

  test('LGA lookup helpers', () => {
    assert.deepEqual(lgaPairs('obi'), [['Benue', 'Obi'], ['Nasarawa', 'Obi']]);
    assert.deepEqual(lgaPairs('nowhere at all'), []);
    assert.equal(canonicalLga('Benue', '  mAkUrDi '), 'Makurdi');
    assert.equal(canonicalLga('Lagos', 'Makurdi'), null);
    // Exactly these 6 of the 770 LGA names occur in more than one state.
    const ambiguous = [...new Set(
      Object.values(NIGERIA_LGAS_BY_STATE).flat().filter(isAmbiguousLga),
    )].sort();
    assert.deepEqual(ambiguous, ['Bassa', 'Ifelodun', 'Irepodun', 'Nasarawa', 'Obi', 'Surulere']);
    assert.ok(isAllLgas('all') && isAllLgas(' All ') && isAllLgas(''));
    assert.ok(!isAllLgas('Obi'));
  });
});
