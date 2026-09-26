import { test, describe } from 'node:test';
import assert from 'node:assert/strict';

import {
  toIso, isUuid, asBool, asInt, refId, normalizeReportStatus, normalizeSeverity,
  normalizeAlertSeverity, normalizeRole, normalizeOverrideAction, isPhoneEmail,
  phoneFromFakeEmail, toE164, extractStoragePath, storageTargetFor, rewriteUrl, cleanImageUrl,
  transformUser, transformReport, transformVerification, transformVerificationOverride,
  transformAlert, transformMessage, transformContact, transformKnowledge, transformAuthority,
  transformTrustedDevice, transformLoginHistory, transformNdpaConsent, decodeHtmlEntities,
} from '../src/transform.js';

const NOW = '2026-09-25T00:00:00.000Z';
const users = { alice: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', bob: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' };
const reports = { r1: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc' };
const ctx = {
  now: NOW,
  user: (uid) => users[uid] ?? null,
  report: (id) => reports[id] ?? null,
  url: (u) => u,
};
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
