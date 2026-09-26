// ─────────────────────────────────────────────────────────────────────────────
// TEST HARNESS ONLY — in-memory Supabase mock for the CRADI *mobile* app.
//
// Adapted from CRADI-Mobile-Admin/e2e/mock-supabase.mjs. Implements the
// subset of Supabase the Flutter app talks to:
//   * GoTrue auth  : /auth/v1/{token,signup,user,logout,recover,otp,verify,resend}
//   * PostgREST    : /rest/v1/<table> (select/filter/order/limit/range/count)
//   * Realtime     : ws://…/realtime/v1/websocket (phoenix v2 protocol)
//   * Storage      : /storage/v1/object/... (upload + public read)
//
// It never talks to any real Supabase project.
//
//   node web_smoke/mock-supabase.mjs        # listens on 127.0.0.1:54321
//
// Test-control endpoints (not part of Supabase):
//   POST /__mock/reset      restore the seed data and clear the request log
//   GET  /__mock/requests   request log [{ method, path, query, prefer, body }]
//   GET  /__mock/table/:t   current rows of a table
//   GET  /__mock/health     liveness
import http from 'node:http';
import crypto, { randomUUID, randomBytes } from 'node:crypto';

const HOST = process.env.MOCK_SUPABASE_HOST || '127.0.0.1';
const PORT = Number(process.env.MOCK_SUPABASE_PORT || 54321);

const uid = (n) => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;

// One account per role, plus edge-case accounts.
const IDS = {
    user: uid(1),
    ewm: uid(2),
    ewv: uid(3),
    ewr: uid(4),
    ldp: uid(5),
    staff: uid(6),
    admin: uid(7),
    tech: uid(8),
    pending: uid(9), // approved = false  → /pending-approval
    unverified: uid(10), // email unconfirmed → /verify-access-code
    disabled: uid(11),
};

const PASSWORD = 'Password123!';

// Columns per table — copied from lib/core/services/supabase_mapping.dart
// (SupabaseSchema.columns), which mirrors supabase/migrations/*_init.sql.
// Unknown columns in select / filters / order / bodies are rejected like
// PostgREST does (42703): that is how the harness catches the app sending a
// column that does not exist.
const SCHEMA = {
    profiles: {
        pk: 'id',
        columns: ['id', 'email', 'name', 'role', 'address', 'state', 'lga', 'ward', 'phone', 'is_verified', 'is_approved', 'is_disabled', 'biometrics_enabled', 'profile_image_url', 'monitoring_zone', 'registration_code', 'last_login_at', 'legacy_firebase_uid', 'created_at', 'updated_at'],
        defaults: { name: 'User', role: 'user', address: '', state: '', lga: '', ward: '', phone: '', is_verified: false, is_approved: false, is_disabled: false, biometrics_enabled: false },
    },
    reports: {
        pk: 'id',
        columns: ['id', 'user_id', 'reporter_name', 'hazard_type', 'severity', 'latitude', 'longitude', 'location_details', 'location', 'address', 'ward', 'lga', 'state', 'description', 'submitted_at', 'image_urls', 'status', 'type', 'is_alert', 'verification_count', 'verified_at', 'auto_validated', 'approved_at', 'rejected_at', 'rejection_reason', 'escalated', 'escalated_at', 'escalation_reason', 'escalation_scheduled_at', 'escalation_status', 'updated_by', 'synced_at', 'legacy_firebase_id', 'created_at', 'updated_at'],
        defaults: { severity: 'medium', location_details: '', location: '', address: '', ward: '', state: '', description: '', image_urls: [], status: 'pending', is_alert: false, verification_count: 0, auto_validated: false, escalated: false },
    },
    scheduled_escalations: {
        pk: 'id',
        columns: ['id', 'report_id', 'escalate_at', 'status', 'reason', 'processed_at', 'created_at', 'updated_at'],
        defaults: { status: 'pending' },
    },
    verifications: {
        pk: 'id',
        columns: ['id', 'report_id', 'verifier_id', 'is_confirmed', 'comment', 'submitted_at', 'created_at', 'updated_at'],
        defaults: { is_confirmed: true, comment: null },
    },
    verification_overrides: {
        pk: 'id',
        columns: ['id', 'report_id', 'validator_id', 'action', 'reason', 'created_at'],
        defaults: {},
    },
    alerts: {
        pk: 'id',
        columns: ['id', 'title', 'message', 'severity', 'target_lga', 'target_state', 'report_id', 'created_by', 'is_active', 'created_at', 'updated_at'],
        defaults: { message: '', severity: 'info', target_lga: 'All', target_state: null, is_active: true },
    },
    messages: {
        pk: 'id',
        columns: ['id', 'chat_id', 'sender_id', 'sender_name', 'message', 'type', 'sent_at', 'read', 'created_at', 'updated_at'],
        defaults: { type: 'text', read: false },
    },
    contacts: {
        pk: 'id',
        columns: ['id', 'user_id', 'name', 'role', 'phone', 'organization', 'lga', 'category', 'is_available', 'created_at', 'updated_at'],
        defaults: { role: '', category: 'other', is_available: true },
    },
    knowledge_base: {
        pk: 'id',
        columns: ['id', 'title', 'content', 'source', 'category', 'hazard_type', 'image_url', 'legacy_firebase_id', 'created_at', 'updated_at'],
        defaults: { content: '', source: '', category: 'General', hazard_type: 'general', image_url: null },
    },
    authorities: {
        pk: 'id',
        columns: ['id', 'name', 'organization', 'phone', 'coverage_lga', 'coverage_state', 'created_at', 'updated_at'],
        defaults: { name: '', organization: null, coverage_state: null },
    },
    trusted_devices: {
        pk: 'id',
        columns: ['id', 'user_id', 'device_fingerprint', 'device_name', 'trusted', 'last_used', 'created_at'],
        defaults: { trusted: false },
    },
    login_history: {
        pk: 'id',
        columns: ['id', 'user_id', 'success', 'device_fingerprint', 'device_name', 'risk_score', 'occurred_at', 'created_at'],
        defaults: { success: true, risk_score: 0 },
    },
    ndpa_consents: {
        pk: 'user_id',
        columns: ['user_id', 'consented_at', 'policy_version', 'data_residency', 'platform', 'method'],
        defaults: {},
    },
    app_settings: { pk: 'key', columns: ['key', 'value', 'updated_at'], defaults: {} },
    news_links: {
        pk: 'id',
        columns: ['id', 'title', 'url', 'source', 'sort_order', 'is_active', 'created_at', 'updated_at'],
        defaults: { source: '', sort_order: 0, is_active: true },
    },
};

const NOT_NULL = {
    reports: ['hazard_type', 'lga'],
    alerts: ['title'],
    authorities: ['phone', 'coverage_lga'],
    knowledge_base: ['title'],
    app_settings: ['value'],
    news_links: ['title', 'url', 'source', 'sort_order', 'is_active'],
    verifications: ['report_id', 'verifier_id'],
    messages: ['chat_id', 'sender_id'],
    contacts: ['name', 'phone'],
};

function iso(daysAgo, minutes = 0) {
    return new Date(Date.now() - daysAgo * 86400000 - minutes * 60000).toISOString();
}

function profile(id, fields) {
    return {
        id, email: null, name: 'User', role: 'user', address: '', state: 'Benue', lga: 'Makurdi', ward: 'Agan', phone: '',
        is_verified: true, is_approved: true, is_disabled: false, biometrics_enabled: false,
        profile_image_url: '', monitoring_zone: '', registration_code: null, last_login_at: iso(1),
        legacy_firebase_uid: null, created_at: iso(30), updated_at: iso(30), ...fields,
    };
}

const HAZARDS = ['Flooding', 'Extreme Temperatures', 'Drought', 'Windstorms', 'Wildfires', 'Erosion', 'Pest Outbreak', 'Crop Disease', 'Conflict'];
const SEVERITIES = ['low', 'medium', 'high', 'critical'];
const STATUSES = ['pending', 'verified', 'approved', 'rejected'];

function report(n, fields) {
    const id = `10000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
    return {
        id, user_id: IDS.user, reporter_name: 'Ada Reporter', hazard_type: 'Flooding', severity: 'medium',
        latitude: 7.7322, longitude: 8.5391, location_details: 'Near the river bank', location: 'Makurdi, Benue',
        address: 'Wurukum, Makurdi', ward: 'Agan', lga: 'Makurdi', state: 'Benue', description: 'Seeded report',
        submitted_at: iso(0, n * 37), image_urls: [], status: 'pending', type: null, is_alert: false,
        verification_count: 0, verified_at: null, auto_validated: false, approved_at: null, rejected_at: null,
        rejection_reason: null, escalated: false, escalated_at: null, escalation_reason: null,
        escalation_scheduled_at: null, escalation_status: null, updated_by: null, synced_at: null,
        legacy_firebase_id: null, created_at: iso(0, n * 37), updated_at: iso(0, n * 37), ...fields,
    };
}

function seed() {
    const authUsers = [
        { id: IDS.user, email: 'user@cradi.test', password: PASSWORD, email_confirmed_at: iso(30), phone_confirmed_at: null, banned_until: null },
        { id: IDS.ewm, email: 'ewm@cradi.test', password: PASSWORD, email_confirmed_at: iso(30), phone_confirmed_at: null, banned_until: null },
        { id: IDS.ewv, email: 'ewv@cradi.test', password: PASSWORD, email_confirmed_at: iso(30), phone_confirmed_at: null, banned_until: null },
        { id: IDS.ewr, email: 'ewr@cradi.test', password: PASSWORD, email_confirmed_at: iso(30), phone_confirmed_at: null, banned_until: null },
        { id: IDS.ldp, email: 'ldp@cradi.test', password: PASSWORD, email_confirmed_at: iso(30), phone_confirmed_at: null, banned_until: null },
        { id: IDS.staff, email: 'staff@cradi.test', password: PASSWORD, email_confirmed_at: iso(30), phone_confirmed_at: null, banned_until: null },
        { id: IDS.admin, email: 'admin@cradi.test', password: PASSWORD, email_confirmed_at: iso(30), phone_confirmed_at: null, banned_until: null },
        { id: IDS.tech, email: 'tech@cradi.test', password: PASSWORD, email_confirmed_at: iso(30), phone_confirmed_at: null, banned_until: null },
        { id: IDS.pending, email: 'pending@cradi.test', password: PASSWORD, email_confirmed_at: iso(2), phone_confirmed_at: null, banned_until: null },
        // Email never confirmed. `allowUnconfirmedLogin` lets the harness sign
        // in anyway so the /verify-access-code screen can be reached.
        { id: IDS.unverified, email: 'unverified@cradi.test', password: PASSWORD, email_confirmed_at: null, phone_confirmed_at: null, banned_until: null, allowUnconfirmedLogin: true },
        { id: IDS.disabled, email: 'disabled@cradi.test', password: PASSWORD, email_confirmed_at: iso(30), phone_confirmed_at: null, banned_until: null },
    ];
    const profiles = [
        profile(IDS.user, { email: 'user@cradi.test', name: 'Ada Reporter', role: 'user', phone: '+2348030000001' }),
        profile(IDS.ewm, { email: 'ewm@cradi.test', name: 'Musa Monitor', role: 'ewm', phone: '+2348030000002', lga: 'Makurdi', ward: 'Agan' }),
        profile(IDS.ewv, { email: 'ewv@cradi.test', name: 'Ngozi Validator', role: 'ewv', phone: '+2348030000003', lga: 'Makurdi', ward: 'Agan' }),
        profile(IDS.ewr, { email: 'ewr@cradi.test', name: 'Bala Responder', role: 'ewr', phone: '+2348030000004', lga: 'Makurdi', ward: 'Agan' }),
        profile(IDS.ldp, { email: 'ldp@cradi.test', name: 'Comfort Coordinator', role: 'ldp_coordinator', phone: '+2348030000005' }),
        profile(IDS.staff, { email: 'staff@cradi.test', name: 'Seyi Staff', role: 'project_staff', phone: '+2348030000006' }),
        profile(IDS.admin, { email: 'admin@cradi.test', name: 'Grace Admin', role: 'admin', phone: '+2348030000007' }),
        profile(IDS.tech, { email: 'tech@cradi.test', name: 'Tunde Tech', role: 'techSupport', phone: '+2348030000008' }),
        profile(IDS.pending, { email: 'pending@cradi.test', name: 'Paul Pending', role: 'ewm', is_approved: false, created_at: iso(2) }),
        profile(IDS.unverified, { email: 'unverified@cradi.test', name: 'Uche Unverified', role: 'user', is_verified: false, is_approved: false, created_at: iso(1) }),
        profile(IDS.disabled, { email: 'disabled@cradi.test', name: 'Dele Disabled', role: 'ewv', is_disabled: true }),
    ];

    // 9 hazard categories × several statuses/severities, spread over reporters.
    const reports = [];
    let n = 1;
    for (const [h, hazard] of HAZARDS.entries()) {
        for (let k = 0; k < 3; k++) {
            const status = STATUSES[(h + k) % STATUSES.length];
            reports.push(report(n++, {
                hazard_type: hazard,
                severity: SEVERITIES[(h + k) % SEVERITIES.length],
                status,
                description: `${hazard} reported near ${['Wurukum', 'North Bank', 'Gboko Road'][k]} — seeded sample ${k + 1}.`,
                user_id: [IDS.user, IDS.ewm, IDS.ldp][k],
                reporter_name: ['Ada Reporter', 'Musa Monitor', 'Comfort Coordinator'][k],
                lga: ['Makurdi', 'Makurdi', 'Gboko'][k],
                ward: ['Agan', 'Agan', 'Yandev'][k],
                verification_count: status === 'verified' || status === 'approved' ? 2 : 0,
                verified_at: status === 'verified' || status === 'approved' ? iso(0, 60) : null,
                approved_at: status === 'approved' ? iso(0, 30) : null,
                rejected_at: status === 'rejected' ? iso(0, 30) : null,
                rejection_reason: status === 'rejected' ? 'Could not be confirmed on the ground' : null,
                image_urls: k === 0 ? [`http://${HOST}:${PORT}/storage/v1/object/public/report-images/seed/${hazard.replace(/\s+/g, '-').toLowerCase()}.jpg`] : [],
            }));
        }
    }
    // Outstanding verification requests (type = 'verification_request').
    reports.push(report(n++, { hazard_type: 'Flooding', type: 'verification_request', status: 'pending', description: 'Please verify: water rising at the bridge', user_id: IDS.ewv, reporter_name: 'Ngozi Validator' }));
    reports.push(report(n++, { hazard_type: 'Windstorms', type: 'verification_request', status: 'pending', description: 'Please verify: roofs blown off at the market', user_id: IDS.ewr, reporter_name: 'Bala Responder' }));
    // Legacy hazard spelling + an escalated report.
    reports.push(report(n++, { hazard_type: 'floods', description: 'Legacy hazard spelling row' }));
    reports.push(report(n++, { hazard_type: 'Conflict', status: 'verified', escalated: true, escalated_at: iso(0, 20), escalation_reason: 'No response within the window', escalation_status: 'sent', verification_count: 3 }));

    const verifications = [
        { id: randomUUID(), report_id: reports[1].id, verifier_id: IDS.ewv, is_confirmed: true, comment: 'Confirmed on site', submitted_at: iso(0, 55), created_at: iso(0, 55), updated_at: iso(0, 55) },
        { id: randomUUID(), report_id: reports[1].id, verifier_id: IDS.ewr, is_confirmed: false, comment: 'Water had receded by the time I arrived', submitted_at: iso(0, 45), created_at: iso(0, 45), updated_at: iso(0, 45) },
    ];

    const alerts = [
        { id: uid(101), title: 'Flood warning — Makurdi', message: 'River Benue is above the danger line. Move to higher ground and keep children away from the water.', severity: 'critical', target_lga: 'Makurdi', target_state: 'Benue', report_id: reports[0].id, created_by: IDS.admin, is_active: true, created_at: iso(0, 15), updated_at: iso(0, 15) },
        { id: uid(102), title: 'Heat advisory', message: 'Temperatures above 40°C expected for the next three days. Stay hydrated.', severity: 'warning', target_lga: 'All', target_state: null, report_id: null, created_by: IDS.ewv, is_active: true, created_at: iso(1), updated_at: iso(1) },
        { id: uid(103), title: 'Windstorm advisory — Gboko', message: 'Secure loose roofing sheets ahead of tonight’s storm.', severity: 'warning', target_lga: 'Gboko', target_state: 'Benue', report_id: null, created_by: IDS.ewr, is_active: true, created_at: iso(2), updated_at: iso(2) },
        { id: uid(104), title: 'Routine drill notice', message: 'A preparedness drill takes place on Saturday.', severity: 'info', target_lga: 'All', target_state: null, report_id: null, created_by: IDS.admin, is_active: true, created_at: iso(3), updated_at: iso(3) },
        { id: uid(105), title: 'Expired drill', message: 'Past exercise, dismissed.', severity: 'info', target_lga: 'All', target_state: null, report_id: null, created_by: IDS.admin, is_active: false, created_at: iso(9), updated_at: iso(9) },
    ];

    const kb = (i, title, category, hazard_type, content, source) => ({
        id: uid(200 + i), title, content, source, category, hazard_type, image_url: null,
        legacy_firebase_id: null, created_at: iso(5 + i), updated_at: iso(5 + i),
    });
    const knowledge_base = [
        kb(1, 'Flood safety basics', 'Flooding', 'Flooding', 'Move to higher ground as soon as water starts rising. Never walk or drive through moving flood water — 15cm is enough to knock an adult off their feet. Switch off electricity at the mains before you leave.', 'NEMA'),
        kb(2, 'Surviving a heatwave', 'Extreme Temperatures', 'Extreme Temperatures', 'Drink water regularly even when you are not thirsty. Keep out of direct sun between 11am and 4pm, and check on elderly neighbours twice a day.', 'NiMet'),
        kb(3, 'Preparing for drought', 'Drought', 'Drought', 'Harvest and store rainwater early in the season, mulch your plots to keep moisture in the soil, and plant short-duration, drought-tolerant varieties.', 'FAO'),
        kb(4, 'Windstorm preparedness', 'Windstorms', 'Windstorms', 'Nail down roofing sheets before the storm season, trim branches overhanging the house, and agree a safe room with your family.', 'NEMA'),
        kb(5, 'Stopping bush fires spreading', 'Wildfires', 'Wildfires', 'Clear a firebreak of at least 3 metres around homesteads and stores. Never leave a cooking or clearing fire unattended.', 'Forestry Dept'),
        kb(6, 'Gully erosion control', 'Erosion', 'Erosion', 'Plant vetiver grass along contours, build check dams in active gullies, and divert roof runoff away from the gully head.', 'NEWMAP'),
        kb(7, 'Responding to a pest outbreak', 'Pest Outbreak', 'Pest Outbreak', 'Scout fields weekly, report unusual swarms immediately, and use recommended biopesticides rather than untested mixtures.', 'IITA'),
        kb(8, 'Recognising crop disease', 'Crop Disease', 'Crop Disease', 'Look for mosaic patterns, wilting and leaf spots. Remove and burn infected plants and never replant from infected stock.', 'IITA'),
        kb(9, 'Staying safe during conflict', 'Conflict', 'Conflict', 'Agree a meeting point with your household, keep documents together, and follow instructions from the nearest security post.', 'Red Cross'),
        kb(10, 'What early warning means for you', 'General', 'general', 'An early warning tells you a hazard is likely, not certain. Act on the advice given rather than waiting for the hazard to arrive.', 'UNDRR'),
        kb(11, 'Legacy floods guide', 'Floods', 'flooding', 'Older article stored under a legacy category spelling.', 'NiMet'),
    ];

    const contacts = [
        { id: uid(301), user_id: IDS.admin, name: 'Police Emergency', role: 'Emergency line', phone: '112', organization: 'Nigeria Police Force', lga: null, category: 'police', is_available: true, created_at: iso(5), updated_at: iso(5) },
        { id: uid(302), user_id: IDS.admin, name: 'Fire Service', role: 'Emergency line', phone: '113', organization: 'Federal Fire Service', lga: null, category: 'fire', is_available: true, created_at: iso(5), updated_at: iso(5) },
        { id: uid(303), user_id: IDS.admin, name: 'Benue SEMA', role: 'Disaster response', phone: '+2348031234567', organization: 'SEMA Benue', lga: 'Makurdi', category: 'disaster', is_available: true, created_at: iso(5), updated_at: iso(5) },
        { id: uid(304), user_id: IDS.user, name: 'Wurukum Clinic', role: 'Health', phone: '+2348039876543', organization: 'PHC', lga: 'Makurdi', category: 'health', is_available: true, created_at: iso(4), updated_at: iso(4) },
        { id: uid(305), user_id: IDS.user, name: 'Ward Head', role: 'Community', phone: '+2348037777777', organization: null, lga: 'Makurdi', category: 'other', is_available: false, created_at: iso(4), updated_at: iso(4) },
    ];

    const messages = [
        { id: uid(401), chat_id: 'general', sender_id: IDS.ewm, sender_name: 'Musa Monitor', message: 'Water level at the bridge is still rising.', type: 'text', sent_at: iso(0, 90), read: true, created_at: iso(0, 90), updated_at: iso(0, 90) },
        { id: uid(402), chat_id: 'general', sender_id: IDS.ewv, sender_name: 'Ngozi Validator', message: 'Noted — I am heading there now.', type: 'text', sent_at: iso(0, 80), read: true, created_at: iso(0, 80), updated_at: iso(0, 80) },
        { id: uid(403), chat_id: 'general', sender_id: IDS.admin, sender_name: 'Grace Admin', message: 'Alert has been broadcast to Makurdi.', type: 'text', sent_at: iso(0, 70), read: false, created_at: iso(0, 70), updated_at: iso(0, 70) },
    ];

    const authorities = [
        { id: uid(501), name: 'Makurdi Emergency Desk', organization: 'SEMA Benue', phone: '+2348031234567', coverage_lga: 'Makurdi', coverage_state: 'Benue', created_at: iso(9), updated_at: iso(9) },
        { id: uid(502), name: 'Gboko Response Unit', organization: 'LEMC', phone: '+2348039999999', coverage_lga: 'Gboko', coverage_state: 'Benue', created_at: iso(8), updated_at: iso(8) },
    ];

    const app_settings = [
        { key: 'minimum_peer_confirmations', value: 2, updated_at: iso(6) },
        { key: 'escalation_timeout_minutes', value: 30, updated_at: iso(6) },
        { key: 'max_sms_per_lga_per_day', value: 50, updated_at: iso(6) },
        { key: 'max_sms_per_alert_event', value: 20, updated_at: iso(6) },
        { key: 'feature_flag_peer_chat', value: true, updated_at: iso(6) },
        { key: 'app_min_version', value: '1.0.0', updated_at: iso(6) },
        { key: 'app_min_version_message', value: '', updated_at: iso(6) },
        { key: 'support_email', value: 'support@cradi.org', updated_at: iso(6) },
    ];

    const news_links = [
        { id: uid(601), title: 'Flood Safety: What to do before, during, and after', url: 'https://www.redcross.org/get-help/how-to-prepare-for-emergencies/types-of-emergencies/flood.html', source: 'Safety Guide', sort_order: 10, is_active: true, created_at: iso(3), updated_at: iso(3) },
        { id: uid(602), title: 'NiMet Seasonal Climate Prediction', url: 'https://nimet.gov.ng/', source: 'NiMet', sort_order: 20, is_active: true, created_at: iso(3), updated_at: iso(3) },
        { id: uid(603), title: 'Emergency Contact Directory: Nigeria', url: 'https://www.redcrossnigeria.org/', source: 'Red Cross', sort_order: 30, is_active: true, created_at: iso(3), updated_at: iso(3) },
        { id: uid(604), title: 'Understanding Early Warning Systems', url: 'https://www.undrr.org/terminology/early-warning-system', source: 'UNDRR', sort_order: 40, is_active: true, created_at: iso(3), updated_at: iso(3) },
        { id: uid(605), title: 'Archived bulletin', url: 'http://example.org/old-bulletin', source: '', sort_order: 50, is_active: false, created_at: iso(2), updated_at: iso(2) },
    ];

    return {
        authUsers,
        tables: {
            profiles, reports, verifications, verification_overrides: [], scheduled_escalations: [],
            alerts, messages, contacts, knowledge_base, authorities, trusted_devices: [],
            login_history: [], ndpa_consents: [], app_settings, news_links,
        },
        sessions: new Map(),
        refresh: new Map(),
        otps: new Map(), // email → { code, type }
        storage: new Map(), // `${bucket}/${path}` → Buffer
    };
}

// 1×1 transparent PNG served for every Storage object that was never uploaded.
const PNG_1PX = Buffer.from(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
    'base64',
);

/** PostgREST `max-rows` as configured on Supabase. */
const MAX_ROWS = 1000;

/** Every OTP the mock issues (sign-up confirmation, recovery, phone). */
const FIXED_OTP = '123456';

let state = seed();
let requestLog = [];

// ── HTTP helpers ────────────────────────────────────────────────────────────

const CORS = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PATCH, PUT, DELETE, HEAD, OPTIONS',
    'Access-Control-Allow-Headers':
        'authorization, apikey, content-type, prefer, range, range-unit, accept, accept-profile, content-profile, x-client-info, x-supabase-api-version',
    'Access-Control-Expose-Headers': 'content-range, x-supabase-api-version',
    'Access-Control-Max-Age': '600',
};

function send(res, status, body, headers = {}) {
    const payload = body === undefined ? '' : JSON.stringify(body);
    res.writeHead(status, {
        ...CORS,
        ...(payload ? { 'Content-Type': 'application/json; charset=utf-8' } : {}),
        ...headers,
    });
    res.end(res.req.method === 'HEAD' ? undefined : payload);
}

function pgError(res, status, code, message) {
    send(res, status, { code, message, details: null, hint: null });
}

function authError(res, status, code, msg) {
    send(res, status, { code, error_code: code, msg }, { 'x-supabase-api-version': '2024-01-01' });
}

function readBody(req) {
    return new Promise((resolve, reject) => {
        const chunks = [];
        req.on('data', (c) => chunks.push(c));
        req.on('end', () => {
            const text = Buffer.concat(chunks).toString('utf8');
            if (!text) return resolve(undefined);
            try {
                resolve(JSON.parse(text));
            } catch {
                reject(new Error('Invalid JSON body'));
            }
        });
        req.on('error', reject);
    });
}

// ── Auth (GoTrue subset) ────────────────────────────────────────────────────

function b64url(obj) {
    return Buffer.from(JSON.stringify(obj)).toString('base64url');
}

function publicUser(u) {
    return {
        id: u.id,
        aud: 'authenticated',
        role: 'authenticated',
        email: u.email,
        email_confirmed_at: u.email_confirmed_at,
        phone: '',
        phone_confirmed_at: u.phone_confirmed_at,
        confirmed_at: u.email_confirmed_at ?? u.phone_confirmed_at,
        banned_until: u.banned_until,
        app_metadata: { provider: 'email', providers: ['email'] },
        user_metadata: u.user_metadata ?? {},
        identities: [],
        created_at: '2026-09-01T00:00:00Z',
        updated_at: '2026-09-01T00:00:00Z',
    };
}

function newSession(u) {
    const now = Math.floor(Date.now() / 1000);
    const expiresIn = 3600;
    const accessToken = [
        b64url({ alg: 'HS256', typ: 'JWT' }),
        b64url({ sub: u.id, email: u.email, role: 'authenticated', aud: 'authenticated', iat: now, exp: now + expiresIn, session_id: randomUUID() }),
        randomBytes(16).toString('base64url'),
    ].join('.');
    const refreshToken = randomBytes(12).toString('hex');
    state.sessions.set(accessToken, u.id);
    state.refresh.set(refreshToken, u.id);
    return {
        access_token: accessToken,
        token_type: 'bearer',
        expires_in: expiresIn,
        expires_at: now + expiresIn,
        refresh_token: refreshToken,
        user: publicUser(u),
    };
}

function isBanned(u) {
    return !!u.banned_until && new Date(u.banned_until).getTime() > Date.now();
}

function bearer(req) {
    const m = (req.headers.authorization || '').match(/^Bearer\s+(\S+)$/i);
    return m ? m[1] : null;
}

const SERVICE_KEY = process.env.MOCK_SUPABASE_SERVICE_KEY || 'test';

async function handleAuth(req, res, url, body) {
    const path = url.pathname.replace(/^\/auth\/v1/, '');
    if (path === '/token' && req.method === 'POST') {
        const grant = url.searchParams.get('grant_type');
        if (grant === 'password') {
            const u = state.authUsers.find((x) => x.email === String(body?.email ?? '').toLowerCase());
            if (!u || u.password !== body?.password) return authError(res, 400, 'invalid_credentials', 'Invalid login credentials');
            if (!u.email_confirmed_at && !u.allowUnconfirmedLogin) return authError(res, 400, 'email_not_confirmed', 'Email not confirmed');
            if (isBanned(u)) return authError(res, 400, 'user_banned', 'User is banned');
            return send(res, 200, newSession(u));
        }
        if (grant === 'refresh_token') {
            const uid = state.refresh.get(body?.refresh_token);
            const u = uid && state.authUsers.find((x) => x.id === uid);
            if (!u) return authError(res, 400, 'refresh_token_not_found', 'Invalid Refresh Token');
            state.refresh.delete(body.refresh_token);
            return send(res, 200, newSession(u));
        }
        return authError(res, 400, 'validation_failed', 'Unsupported grant type');
    }
    if (path === '/user' && req.method === 'GET') {
        const uid = state.sessions.get(bearer(req));
        const u = uid && state.authUsers.find((x) => x.id === uid);
        if (!u) return authError(res, 403, 'bad_jwt', 'invalid JWT');
        return send(res, 200, publicUser(u));
    }
    if (path === '/logout' && req.method === 'POST') {
        state.sessions.delete(bearer(req));
        return send(res, 204);
    }
    const admin = path.match(/^\/admin\/users\/([^/]+)$/);
    if (admin) {
        if (bearer(req) !== SERVICE_KEY) return authError(res, 403, 'not_admin', 'User not allowed');
        const u = state.authUsers.find((x) => x.id === admin[1]);
        if (!u) return authError(res, 404, 'user_not_found', 'User not found');
        if (req.method === 'GET') return send(res, 200, publicUser(u));
        if (req.method === 'PUT') {
            if (body && 'ban_duration' in body) {
                u.banned_until = body.ban_duration === 'none' ? null : '2126-01-01T00:00:00Z';
            }
            return send(res, 200, publicUser(u));
        }
        if (req.method === 'DELETE') {
            state.authUsers = state.authUsers.filter((x) => x !== u);
            state.tables.profiles = state.tables.profiles.filter((p) => p.id !== u.id); // ON DELETE CASCADE
            return send(res, 200, {});
        }
    }
    // ── Sign-up (email + password, confirmations ON) ────────────────────────
    if (path === '/signup' && req.method === 'POST') {
        const email = String(body?.email ?? '').toLowerCase().trim();
        const phone = String(body?.phone ?? '').trim();
        if (!email && !phone) return authError(res, 400, 'validation_failed', 'Missing email or phone');
        if (email && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
            return authError(res, 400, 'validation_failed', 'Unable to validate email address: invalid format');
        }
        if (String(body?.password ?? '').length < 8) {
            return authError(res, 422, 'weak_password', 'Password should be at least 8 characters');
        }
        const existing = state.authUsers.find((x) => x.email === email);
        if (existing) {
            // Confirmations on: GoTrue obfuscates and returns a user with no
            // identities rather than leaking that the address is taken.
            return send(res, 200, { ...publicUser(existing), identities: [] });
        }
        const u = {
            id: randomUUID(), email, password: body.password, email_confirmed_at: null,
            phone_confirmed_at: null, banned_until: null, user_metadata: body?.data ?? {},
        };
        state.authUsers.push(u);
        // handle_new_user() trigger: creates the profiles row from metadata.
        const md = u.user_metadata ?? {};
        state.tables.profiles.push({
            ...Object.fromEntries(SCHEMA.profiles.columns.map((c) => [c, null])),
            ...SCHEMA.profiles.defaults,
            id: u.id, email, name: md.name ?? md.full_name ?? 'User', role: md.role ?? 'user',
            phone: md.phone ?? '', state: md.state ?? '', lga: md.lga ?? '', ward: md.ward ?? '',
            address: md.address ?? '', is_verified: false, is_approved: false, is_disabled: false,
            created_at: nowIso(), updated_at: nowIso(),
        });
        state.otps.set(email, { code: FIXED_OTP, type: 'signup' });
        return send(res, 200, { ...publicUser(u), identities: [{ id: u.id, user_id: u.id, provider: 'email' }] });
    }

    // ── Resend a sign-up / recovery code ────────────────────────────────────
    if (path === '/resend' && req.method === 'POST') {
        const email = String(body?.email ?? '').toLowerCase().trim();
        state.otps.set(email, { code: FIXED_OTP, type: body?.type ?? 'signup' });
        return send(res, 200, {});
    }

    // ── Password recovery (emails a 6-digit code) ───────────────────────────
    if (path === '/recover' && req.method === 'POST') {
        const email = String(body?.email ?? '').toLowerCase().trim();
        // GoTrue always answers 200 so addresses cannot be enumerated.
        if (state.authUsers.some((x) => x.email === email)) {
            state.otps.set(email, { code: FIXED_OTP, type: 'recovery' });
        }
        return send(res, 200, {});
    }

    // ── Phone / magic-link OTP ──────────────────────────────────────────────
    if (path === '/otp' && req.method === 'POST') {
        if (body?.phone) return authError(res, 422, 'phone_provider_disabled', 'Phone logins are disabled');
        const email = String(body?.email ?? '').toLowerCase().trim();
        state.otps.set(email, { code: FIXED_OTP, type: 'magiclink' });
        return send(res, 200, {});
    }

    // ── Verify a 6-digit code ───────────────────────────────────────────────
    if (path === '/verify' && req.method === 'POST') {
        const type = body?.type;
        if (body?.phone) return authError(res, 403, 'otp_expired', 'Token has expired or is invalid');
        const email = String(body?.email ?? '').toLowerCase().trim();
        const u = state.authUsers.find((x) => x.email === email);
        const issued = state.otps.get(email);
        if (!u || !issued || String(body?.token ?? '') !== issued.code) {
            return authError(res, 403, 'otp_expired', 'Token has expired or is invalid');
        }
        state.otps.delete(email);
        if (type === 'signup' || type === 'magiclink' || type === 'email') {
            u.email_confirmed_at = u.email_confirmed_at ?? nowIso();
            const p = state.tables.profiles.find((x) => x.id === u.id);
            if (p) p.is_verified = true;
        }
        if (type === 'recovery') u.recovering = true;
        return send(res, 200, newSession(u));
    }

    // ── Update the signed-in user (password change after recovery) ──────────
    if (path === '/user' && req.method === 'PUT') {
        const id = state.sessions.get(bearer(req));
        const u = id && state.authUsers.find((x) => x.id === id);
        if (!u) return authError(res, 401, 'bad_jwt', 'invalid JWT');
        if (body?.password !== undefined) {
            if (String(body.password).length < 8) {
                return authError(res, 422, 'weak_password', 'Password should be at least 8 characters');
            }
            if (body.password === u.password) {
                return authError(res, 422, 'same_password', 'New password should be different from the old password');
            }
            u.password = body.password;
        }
        if (body?.email) u.email = String(body.email).toLowerCase();
        if (body?.data) u.user_metadata = { ...(u.user_metadata ?? {}), ...body.data };
        return send(res, 200, publicUser(u));
    }

    return authError(res, 404, 'not_found', `Mock: no auth route ${req.method} ${path}`);
}

// ── PostgREST subset ────────────────────────────────────────────────────────

class RestError extends Error {
    constructor(status, code, message) {
        super(message);
        this.status = status;
        this.code = code;
    }
}

function checkColumn(table, column) {
    if (!SCHEMA[table].columns.includes(column)) {
        throw new RestError(400, '42703', `column ${table}.${column} does not exist`);
    }
}

/** Splits on commas not inside quotes or parentheses. */
function splitTopLevel(text) {
    const out = [];
    let depth = 0;
    let quoted = false;
    let cur = '';
    for (const ch of text) {
        if (ch === '"') quoted = !quoted;
        if (!quoted && ch === '(') depth += 1;
        if (!quoted && ch === ')') depth -= 1;
        if (!quoted && depth === 0 && ch === ',') {
            out.push(cur);
            cur = '';
        } else cur += ch;
    }
    if (cur !== '') out.push(cur);
    return out;
}

function unquote(v) {
    return v.length >= 2 && v.startsWith('"') && v.endsWith('"') ? v.slice(1, -1) : v;
}

function likeRegex(pattern, flags) {
    const re = pattern
        .split('')
        .map((c) => (c === '*' || c === '%' ? '.*' : c === '_' ? '.' : c.replace(/[.+?^${}()|[\]\\]/g, '\\$&')))
        .join('');
    return new RegExp(`^${re}$`, flags);
}

function asText(value) {
    if (value === null || value === undefined) return null;
    return typeof value === 'object' ? JSON.stringify(value) : String(value);
}

/** Returns a predicate for `column` + `op.value` (PostgREST filter syntax). */
function makeFilter(table, column, expr) {
    checkColumn(table, column);
    let negate = false;
    let rest = expr;
    if (rest.startsWith('not.')) {
        negate = true;
        rest = rest.slice(4);
    }
    const dot = rest.indexOf('.');
    if (dot < 0) throw new RestError(400, 'PGRST100', `failed to parse filter (${expr})`);
    const op = rest.slice(0, dot);
    const raw = rest.slice(dot + 1);
    let pred;
    switch (op) {
        case 'eq':
            pred = (row) => asText(row[column]) === raw;
            break;
        case 'neq':
            pred = (row) => row[column] !== null && asText(row[column]) !== raw;
            break;
        case 'is':
            if (raw === 'null') pred = (row) => row[column] === null || row[column] === undefined;
            else if (raw === 'true' || raw === 'false') pred = (row) => row[column] === (raw === 'true');
            else throw new RestError(400, 'PGRST100', `failed to parse filter (${expr})`);
            break;
        case 'in': {
            if (!raw.startsWith('(') || !raw.endsWith(')')) throw new RestError(400, 'PGRST100', `failed to parse filter (${expr})`);
            const values = splitTopLevel(raw.slice(1, -1)).map(unquote);
            pred = (row) => values.includes(asText(row[column]));
            break;
        }
        case 'like':
        case 'ilike': {
            const re = likeRegex(raw, op === 'ilike' ? 'is' : 's');
            pred = (row) => row[column] !== null && re.test(asText(row[column]));
            break;
        }
        case 'gt':
        case 'gte':
        case 'lt':
        case 'lte':
            pred = (row) => {
                const a = row[column];
                if (a === null) return false;
                const b = typeof a === 'number' ? Number(raw) : raw;
                return op === 'gt' ? a > b : op === 'gte' ? a >= b : op === 'lt' ? a < b : a <= b;
            };
            break;
        default:
            throw new RestError(400, 'PGRST100', `mock: unsupported operator ${op}`);
    }
    return negate ? (row) => !pred(row) : pred;
}

function parseOr(table, expr) {
    if (!expr.startsWith('(') || !expr.endsWith(')')) throw new RestError(400, 'PGRST100', `failed to parse logic tree (${expr})`);
    const preds = splitTopLevel(expr.slice(1, -1)).map((item) => {
        const dot = item.indexOf('.');
        // Inside a logic tree PostgREST accepts double-quoted values ("a,b" / "Akwa Ibom").
        const filter = item.slice(dot + 1).replace(/^((?:not\.)?(?:eq|neq)\.)"(.*)"$/s, (_, op, v) => op + v.replace(/\\(.)/g, '$1'));
        return makeFilter(table, item.slice(0, dot), filter);
    });
    return (row) => preds.some((p) => p(row));
}

const RESERVED = new Set(['select', 'order', 'limit', 'offset', 'on_conflict', 'columns']);

function parseQuery(table, params) {
    const filters = [];
    for (const [key, value] of params) {
        if (RESERVED.has(key)) continue;
        if (key === 'or') filters.push(parseOr(table, value));
        else if (key === 'and') throw new RestError(400, 'PGRST100', 'mock: and= not supported');
        else filters.push(makeFilter(table, key, value));
    }
    let select = null;
    const rawSelect = params.get('select');
    if (rawSelect !== null) {
        select = rawSelect === '*'
            ? null
            : splitTopLevel(rawSelect).map((c) => c.trim()).filter(Boolean);
        for (const c of select ?? []) {
            // `alias:other_table!fk_column(col,…)` — a PostgREST resource embed.
            const embed = parseEmbed(table, c);
            if (embed) continue;
            if (/[():!]/.test(c)) throw new RestError(400, 'PGRST100', `mock: unsupported select ${c}`);
            if (c !== '*') checkColumn(table, c);
        }
    }
    const order = (params.get('order') || '')
        .split(',')
        .filter(Boolean)
        .map((part) => {
            const [column, dir = 'asc', nulls] = part.split('.');
            checkColumn(table, column);
            const desc = dir === 'desc';
            return { column, desc, nullsFirst: nulls ? nulls === 'nullsfirst' : desc };
        });
    const limit = params.has('limit') ? Number(params.get('limit')) : null;
    const offset = params.has('offset') ? Number(params.get('offset')) : 0;
    return { match: (row) => filters.every((f) => f(row)), select, order, limit, offset };
}

function compare(a, b) {
    if (typeof a === 'number' && typeof b === 'number') return a - b;
    if (typeof a === 'boolean' && typeof b === 'boolean') return Number(a) - Number(b);
    const sa = asText(a);
    const sb = asText(b);
    return sa < sb ? -1 : sa > sb ? 1 : 0; // byte order, like the C collation
}

function sortRows(rows, order) {
    return [...rows].sort((x, y) => {
        for (const { column, desc, nullsFirst } of order) {
            const a = x[column] ?? null;
            const b = y[column] ?? null;
            if (a === null || b === null) {
                if (a === b) continue;
                return (a === null) === nullsFirst ? -1 : 1;
            }
            const c = compare(a, b);
            if (c !== 0) return desc ? -c : c;
        }
        return 0;
    });
}

/**
 * Parses a PostgREST resource embed: `alias:table!fk_column(col,…)`.
 * Returns null when [item] is a plain column.
 */
function parseEmbed(table, item) {
    const m = item.match(/^(?:([A-Za-z_][\w]*):)?([a-z_]+)(?:!([a-z_]+))?\((.*)\)$/s);
    if (!m) return null;
    const [, alias, target, fk, cols] = m;
    if (!SCHEMA[target]) throw new RestError(400, 'PGRST200', `mock: no relation ${target}`);
    const fkColumn = fk ?? `${target.replace(/s$/, '')}_id`;
    checkColumn(table, fkColumn);
    const columns = splitTopLevel(cols).map((c) => c.trim()).filter(Boolean);
    for (const c of columns) if (c !== '*') checkColumn(target, c);
    return { key: alias ?? target, target, fkColumn, columns };
}

function project(row, select, table) {
    if (!select) return { ...row };
    const out = {};
    for (const item of select) {
        const embed = table ? parseEmbed(table, item) : null;
        if (embed) {
            const ref = (state.tables[embed.target] ?? []).find(
                (r) => r[SCHEMA[embed.target].pk] === row[embed.fkColumn],
            );
            out[embed.key] = ref
                ? (embed.columns.includes('*')
                    ? { ...ref }
                    : Object.fromEntries(embed.columns.map((c) => [c, ref[c] ?? null])))
                : null;
            continue;
        }
        if (item === '*') {
            Object.assign(out, row);
            continue;
        }
        out[item] = row[item] ?? null;
    }
    return out;
}

function checkBody(table, row) {
    if (typeof row !== 'object' || row === null || Array.isArray(row)) throw new RestError(400, 'PGRST102', 'Invalid body');
    for (const key of Object.keys(row)) checkColumn(table, key);
}

function checkNotNull(table, row) {
    for (const c of NOT_NULL[table] ?? []) {
        if (row[c] === null || row[c] === undefined) {
            throw new RestError(400, '23502', `null value in column "${c}" of relation "${table}" violates not-null constraint`);
        }
    }
}

/** Check constraints evaluated on every insert and update. */
function checkConstraints(table, row) {
    // 20260927050000_alert_target_state.sql: NULL, or a non-blank, unpadded name.
    if (table === 'alerts' && row.target_state != null) {
        const v = row.target_state;
        if (typeof v !== 'string' || v !== v.trim() || v === '') {
            throw new RestError(400, '23514', 'new row for relation "alerts" violates check constraint "alerts_target_state_check"');
        }
    }
    if (table === 'news_links') {
        const violation = (name) =>
            new RestError(400, '23514', `new row for relation "news_links" violates check constraint "${name}"`);
        const title = typeof row.title === 'string' ? row.title.trim() : '';
        if (title.length < 1 || title.length > 300) throw violation('news_links_title_check');
        if (typeof row.url !== 'string' || !/^https?:\/\/\S+$/i.test(row.url) || row.url.length > 2000) {
            throw violation('news_links_url_check');
        }
        if (typeof row.source !== 'string' || row.source.length > 120) throw violation('news_links_source_check');
        if (!Number.isInteger(row.sort_order)) throw new RestError(400, '22P02', 'invalid input syntax for type integer');
    }
}

/** The user id of the request being handled (for `default auth.uid()`). */
let requestUserId = null;

/** Columns declared `default auth.uid()` in the migrations. */
const AUTH_UID_DEFAULTS = {
    verifications: 'verifier_id',
    verification_overrides: 'validator_id',
    alerts: 'created_by',
    messages: 'sender_id',
    contacts: 'user_id',
    trusted_devices: 'user_id',
    login_history: 'user_id',
    ndpa_consents: 'user_id',
};

/** BEFORE INSERT triggers that fill server-owned columns. */
function beforeInsert(table, row) {
    const uidColumn = AUTH_UID_DEFAULTS[table];
    if (uidColumn && row[uidColumn] == null) row[uidColumn] = requestUserId;
    // reports_before_insert(): reporter_name comes from the profile.
    if (table === 'reports' && row.reporter_name == null && row.user_id) {
        row.reporter_name = state.tables.profiles.find((p) => p.id === row.user_id)?.name ?? null;
    }
    // messages_before_insert(): sender_name comes from the profile.
    if (table === 'messages' && row.sender_name == null && row.sender_id) {
        row.sender_name = state.tables.profiles.find((p) => p.id === row.sender_id)?.name ?? null;
    }
    if (table === 'messages' && row.sent_at == null) row.sent_at = nowIso();
    if (table === 'verifications' && row.submitted_at == null) row.submitted_at = nowIso();
}

/** Database triggers / constraints that matter for the admin panel. */
function beforeUpdate(table, oldRow, newRow) {
    checkConstraints(table, newRow);
    if (table === 'profiles' && newRow.is_approved && !oldRow.is_approved) {
        const u = state.authUsers.find((x) => x.id === newRow.id);
        if (!u || (!u.email_confirmed_at && !u.phone_confirmed_at)) {
            throw new RestError(403, '42501', 'This account has not confirmed its email or phone yet, so it cannot be approved');
        }
    }
    if (table === 'reports') {
        if (newRow.status === 'pending' && oldRow.status !== 'pending') {
            throw new RestError(403, '42501', 'Use reopen_report() to move a report back to pending');
        }
        if (!['pending', 'verified', 'approved', 'rejected'].includes(newRow.status)) {
            throw new RestError(400, '23514', 'new row for relation "reports" violates check constraint "reports_status_check"');
        }
    }
    if (table === 'alerts' && !['info', 'warning', 'critical'].includes(newRow.severity)) {
        throw new RestError(400, '23514', 'new row for relation "alerts" violates check constraint "alerts_severity_check"');
    }
    if (table === 'profiles' && !['user', 'ewm', 'ewv', 'ewr', 'ldp_coordinator', 'project_staff', 'admin', 'techSupport'].includes(newRow.role)) {
        throw new RestError(400, '23514', 'new row for relation "profiles" violates check constraint "profiles_role_check"');
    }
}

function contentRange(offset, count, total) {
    const range = count === 0 ? '*' : `${offset}-${offset + count - 1}`;
    return `${range}/${total ?? '*'}`;
}

function wantsCount(req) {
    return /count=exact/.test(req.headers.prefer || '');
}

function wantsRepresentation(req) {
    return /return=representation/.test(req.headers.prefer || '');
}

function reply(req, res, status, rows, select, total, table) {
    const accept = req.headers.accept || '';
    const projected = rows.map((r) => project(r, select, table));
    const headers = { 'Content-Range': contentRange(0, projected.length, total) };
    if (accept.includes('application/vnd.pgrst.object+json')) {
        if (projected.length !== 1) return pgError(res, 406, 'PGRST116', 'JSON object requested, multiple (or no) rows returned');
        return send(res, status, projected[0], headers);
    }
    return send(res, status, projected, headers);
}

function nowIso() {
    return new Date().toISOString();
}

function handleRpc(req, res, fn, body) {
    if (fn === 'reopen_report') {
        const r = state.tables.reports.find((x) => x.id === body?.p_report_id);
        if (!r) return pgError(res, 400, 'P0002', 'Report not found');
        if (r.status === 'pending') return pgError(res, 400, '22023', 'Report is already pending');
        Object.assign(r, {
            status: 'pending', verification_count: 0, verified_at: null, auto_validated: false, approved_at: null,
            rejected_at: null, rejection_reason: null, escalated: false, escalated_at: null, escalation_reason: null,
            escalation_status: 'pending', updated_at: nowIso(),
        });
        return send(res, 204);
    }
    return pgError(res, 404, 'PGRST202', `Could not find the function public.${fn}`);
}

function handleRest(req, res, url, body) {
    const rpc = url.pathname.match(/^\/rest\/v1\/rpc\/([a-z_]+)$/);
    if (rpc) return handleRpc(req, res, rpc[1], body);

    const m = url.pathname.match(/^\/rest\/v1\/([a-z_]+)$/);
    if (!m || !SCHEMA[m[1]]) return pgError(res, 404, '42P01', `relation "public.${m ? m[1] : url.pathname}" does not exist`);
    const table = m[1];
    const schema = SCHEMA[table];
    const q = parseQuery(table, url.searchParams);
    const rows = state.tables[table];

    if (req.method === 'GET' || req.method === 'HEAD') {
        const matched = sortRows(rows.filter(q.match), q.order);
        // PostgREST max-rows (1000 on Supabase) silently caps every response.
        const limit = Math.min(q.limit ?? MAX_ROWS, MAX_ROWS);
        const page = matched.slice(q.offset, q.offset + limit);
        const total = wantsCount(req) ? matched.length : null;
        const headers = { 'Content-Range': contentRange(q.offset, page.length, total) };
        if (req.method === 'HEAD') return send(res, 200, undefined, headers);
        return send(res, 200, page.map((r) => project(r, q.select, table)), headers);
    }

    if (req.method === 'POST') {
        const items = Array.isArray(body) ? body : [body];
        items.forEach((item) => checkBody(table, item));
        const prefer = req.headers.prefer || '';
        const merge = /resolution=merge-duplicates/.test(prefer);
        const conflict = url.searchParams.get('on_conflict') || schema.pk;
        const written = [];
        for (const item of items) {
            const existing = merge ? rows.find((r) => r[conflict] === item[conflict]) : null;
            if (existing) {
                const next = { ...existing, ...item };
                if (schema.columns.includes('updated_at') && !('updated_at' in item)) next.updated_at = nowIso();
                checkNotNull(table, next);
                beforeUpdate(table, existing, next);
                Object.assign(existing, next);
                written.push(existing);
                continue;
            }
            if (!merge && item[schema.pk] !== undefined && rows.some((r) => r[schema.pk] === item[schema.pk])) {
                throw new RestError(409, '23505', `duplicate key value violates unique constraint "${table}_pkey"`);
            }
            const row = Object.fromEntries(schema.columns.map((c) => [c, null]));
            Object.assign(row, schema.defaults);
            if (schema.pk === 'id') row.id = randomUUID();
            if ('created_at' in row) row.created_at = nowIso();
            if ('updated_at' in row) row.updated_at = nowIso();
            if (table === 'reports') row.submitted_at = nowIso();
            Object.assign(row, item);
            beforeInsert(table, row);
            checkNotNull(table, row);
            checkConstraints(table, row);
            rows.push(row);
            written.push(row);
        }
        if (!wantsRepresentation(req)) return send(res, 201);
        return reply(req, res, 201, written, q.select, null, table);
    }

    if (req.method === 'PATCH') {
        checkBody(table, body);
        const matched = rows.filter(q.match);
        for (const row of matched) {
            const next = { ...row, ...body };
            if (schema.columns.includes('updated_at')) next.updated_at = nowIso(); // touch_updated_at trigger
            checkNotNull(table, next);
            beforeUpdate(table, row, next);
        }
        for (const row of matched) {
            Object.assign(row, body);
            if (schema.columns.includes('updated_at')) row.updated_at = nowIso();
        }
        if (!wantsRepresentation(req)) return send(res, 204);
        return reply(req, res, 200, matched, q.select, null, table);
    }

    if (req.method === 'DELETE') {
        const matched = rows.filter(q.match);
        state.tables[table] = rows.filter((r) => !matched.includes(r));
        if (!wantsRepresentation(req)) return send(res, 204);
        return reply(req, res, 200, matched, q.select, null, table);
    }

    return pgError(res, 405, 'PGRST117', `Unsupported HTTP method: ${req.method}`);
}

// ── Storage (object upload + public read) ───────────────────────────────────

function handleStorage(req, res, url, rawBody) {
    // POST/PUT /storage/v1/object/<bucket>/<path...>
    const upload = url.pathname.match(/^\/storage\/v1\/object\/([^/]+)\/(.+)$/);
    if (upload && (req.method === 'POST' || req.method === 'PUT')) {
        const [, bucket, objectPath] = upload;
        const key = `${bucket}/${objectPath}`;
        const upsert = String(req.headers['x-upsert'] ?? '') === 'true' || req.method === 'PUT';
        if (state.storage.has(key) && !upsert) {
            return send(res, 409, { statusCode: '409', error: 'Duplicate', message: 'The resource already exists' });
        }
        state.storage.set(key, rawBody ?? Buffer.alloc(0));
        return send(res, 200, { Id: randomUUID(), Key: key });
    }
    const get = url.pathname.match(/^\/storage\/v1\/object\/(?:public\/)?([^/]+)\/(.+)$/);
    if (get && (req.method === 'GET' || req.method === 'HEAD')) {
        const bytes = state.storage.get(`${get[1]}/${get[2]}`) ?? PNG_1PX;
        res.writeHead(200, { ...CORS, 'Content-Type': 'image/png', 'Content-Length': bytes.length });
        return res.end(req.method === 'HEAD' ? undefined : bytes);
    }
    if (url.pathname.startsWith('/storage/v1/object/') && req.method === 'DELETE') {
        return send(res, 200, { message: 'Successfully deleted' });
    }
    return send(res, 404, { statusCode: '404', error: 'NotFound', message: `Mock: unknown storage path ${url.pathname}` });
}

// ── Realtime (phoenix v2 protocol over a hand-rolled WebSocket) ─────────────
//
// supabase_flutter's `.stream()` loads its first page over REST, but it also
// opens a realtime channel and surfaces a `channelError` on the stream when
// that channel fails. Without this, every stream-backed screen would show an
// error banner that has nothing to do with the app's own code.

const WS_GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';
/** Open sockets: { socket, bindings: [{ id, event, schema, table, filter, topic, joinRef }] } */
const realtimeSockets = new Set();
let bindingSeq = 0;

function wsEncode(text) {
    const payload = Buffer.from(text, 'utf8');
    const len = payload.length;
    let header;
    if (len < 126) {
        header = Buffer.from([0x81, len]);
    } else if (len < 65536) {
        header = Buffer.alloc(4);
        header[0] = 0x81; header[1] = 126; header.writeUInt16BE(len, 2);
    } else {
        header = Buffer.alloc(10);
        header[0] = 0x81; header[1] = 127; header.writeBigUInt64BE(BigInt(len), 2);
    }
    return Buffer.concat([header, payload]);
}

/** Minimal frame reader: text/close/ping, with client masking. */
function wsFrames(buffer) {
    const out = [];
    let offset = 0;
    while (offset + 2 <= buffer.length) {
        const first = buffer[offset];
        const second = buffer[offset + 1];
        const opcode = first & 0x0f;
        const masked = (second & 0x80) !== 0;
        let len = second & 0x7f;
        let pos = offset + 2;
        if (len === 126) {
            if (pos + 2 > buffer.length) break;
            len = buffer.readUInt16BE(pos); pos += 2;
        } else if (len === 127) {
            if (pos + 8 > buffer.length) break;
            len = Number(buffer.readBigUInt64BE(pos)); pos += 8;
        }
        let mask = null;
        if (masked) {
            if (pos + 4 > buffer.length) break;
            mask = buffer.subarray(pos, pos + 4); pos += 4;
        }
        if (pos + len > buffer.length) break;
        const data = Buffer.from(buffer.subarray(pos, pos + len));
        if (mask) for (let i = 0; i < data.length; i++) data[i] ^= mask[i % 4];
        out.push({ opcode, data });
        offset = pos + len;
    }
    return { frames: out, rest: buffer.subarray(offset) };
}

/** `id=eq.<value>` / `status=eq.pending` — the only filter shape .stream() sends. */
function matchesRealtimeFilter(filter, row) {
    if (!filter) return true;
    const m = String(filter).match(/^([a-z_]+)=([a-z]+)\.(.*)$/);
    if (!m) return true;
    const [, column, op, value] = m;
    const actual = asText(row[column]);
    switch (op) {
        case 'eq': return actual === value;
        case 'neq': return actual !== value;
        case 'gt': return actual > value;
        case 'gte': return actual >= value;
        case 'lt': return actual < value;
        case 'lte': return actual <= value;
        default: return true;
    }
}

function broadcastChange(table, type, record, oldRecord) {
    for (const client of realtimeSockets) {
        const ids = [];
        for (const b of client.bindings) {
            if (b.table !== table && b.table !== '*') continue;
            if (b.event !== '*' && b.event !== type) continue;
            if (!matchesRealtimeFilter(b.filter, type === 'DELETE' ? oldRecord : record)) continue;
            ids.push(b.id);
        }
        if (ids.length === 0) continue;
        const topic = client.bindings.find((b) => ids.includes(b.id)).topic;
        client.send([null, null, topic, 'postgres_changes', {
            ids,
            data: {
                schema: 'public', table, commit_timestamp: nowIso(), type,
                columns: [], // empty: values are already JSON-typed (see transformers.dart)
                record: type === 'DELETE' ? {} : record,
                old_record: type === 'INSERT' ? {} : { id: (oldRecord ?? record)?.id ?? null },
                errors: null,
            },
        }]);
    }
}

function handleUpgrade(req, socket, head) {
    const url = new URL(req.url || '/', `http://${req.headers.host}`);
    if (!url.pathname.startsWith('/realtime/v1/websocket')) {
        socket.destroy();
        return;
    }
    const key = req.headers['sec-websocket-key'];
    const accept = crypto.createHash('sha1').update(key + WS_GUID).digest('base64');
    socket.write(
        'HTTP/1.1 101 Switching Protocols\r\n' +
        'Upgrade: websocket\r\nConnection: Upgrade\r\n' +
        `Sec-WebSocket-Accept: ${accept}\r\n\r\n`,
    );
    socket.setNoDelay(true);

    const client = {
        bindings: [],
        send(message) {
            try {
                socket.write(wsEncode(JSON.stringify(message)));
            } catch {
                /* socket gone */
            }
        },
    };
    realtimeSockets.add(client);

    let buffer = head && head.length ? Buffer.from(head) : Buffer.alloc(0);
    socket.on('data', (chunk) => {
        buffer = Buffer.concat([buffer, chunk]);
        const { frames, rest } = wsFrames(buffer);
        buffer = rest;
        for (const frame of frames) {
            if (frame.opcode === 0x8) { socket.end(); return; }
            if (frame.opcode !== 0x1) continue;
            let msg;
            try {
                msg = JSON.parse(frame.data.toString('utf8'));
            } catch {
                continue;
            }
            const [joinRef, ref, topic, event, payload] = msg;
            if (event === 'phx_join') {
                const requested = payload?.config?.postgres_changes ?? [];
                const echoed = requested.map((f) => {
                    const id = ++bindingSeq;
                    client.bindings.push({
                        id, topic, joinRef,
                        event: f.event ?? '*',
                        schema: f.schema ?? 'public',
                        table: f.table ?? '*',
                        filter: f.filter ?? null,
                    });
                    return { ...f, id };
                });
                client.send([joinRef, ref, topic, 'phx_reply', {
                    status: 'ok',
                    response: { postgres_changes: echoed },
                }]);
            } else if (event === 'heartbeat') {
                client.send([joinRef ?? null, ref, 'phoenix', 'phx_reply', { status: 'ok', response: {} }]);
            } else if (event === 'phx_leave') {
                client.bindings = client.bindings.filter((b) => b.topic !== topic);
                client.send([joinRef, ref, topic, 'phx_reply', { status: 'ok', response: {} }]);
            } else if (ref != null) {
                // access_token, broadcast, presence… — acknowledge so pushes
                // never time out.
                client.send([joinRef ?? null, ref, topic, 'phx_reply', { status: 'ok', response: {} }]);
            }
        }
    });
    const close = () => realtimeSockets.delete(client);
    socket.on('close', close);
    socket.on('error', close);
}

// ── Server ──────────────────────────────────────────────────────────────────

function rawBody(req) {
    return new Promise((resolve) => {
        const chunks = [];
        req.on('data', (c) => chunks.push(c));
        req.on('end', () => resolve(Buffer.concat(chunks)));
        req.on('error', () => resolve(Buffer.alloc(0)));
    });
}

/** Snapshot of a table keyed by primary key, for realtime change detection. */
function snapshot(table) {
    const pk = SCHEMA[table].pk;
    return new Map((state.tables[table] ?? []).map((r) => [r[pk], JSON.stringify(r)]));
}

function emitChanges(table, before) {
    const pk = SCHEMA[table].pk;
    const after = snapshot(table);
    const rows = new Map((state.tables[table] ?? []).map((r) => [r[pk], r]));
    for (const [id, json] of after) {
        if (!before.has(id)) broadcastChange(table, 'INSERT', rows.get(id), null);
        else if (before.get(id) !== json) broadcastChange(table, 'UPDATE', rows.get(id), JSON.parse(before.get(id)));
    }
    for (const [id, json] of before) {
        if (!after.has(id)) broadcastChange(table, 'DELETE', null, JSON.parse(json));
    }
}

const server = http.createServer(async (req, res) => {
    const url = new URL(req.url || '/', `http://${req.headers.host || `${HOST}:${PORT}`}`);
    if (req.method === 'OPTIONS') {
        res.writeHead(204, CORS);
        return res.end();
    }

    const raw = await rawBody(req);
    if (url.pathname.startsWith('/storage/v1/')) return handleStorage(req, res, url, raw);

    let body;
    const text = raw.toString('utf8');
    if (text) {
        try {
            body = JSON.parse(text);
        } catch {
            return pgError(res, 400, 'PGRST102', 'Invalid JSON body');
        }
    }

    if (url.pathname.startsWith('/__mock/')) {
        if (url.pathname === '/__mock/health') return send(res, 200, { ok: true });
        if (url.pathname === '/__mock/reset' && req.method === 'POST') {
            state = seed();
            requestLog = [];
            return send(res, 200, { ok: true });
        }
        if (url.pathname === '/__mock/requests') return send(res, 200, requestLog);
        if (url.pathname === '/__mock/accounts') {
            return send(res, 200, state.authUsers.map((u) => ({ email: u.email, password: u.password, id: u.id })));
        }
        const t = url.pathname.match(/^\/__mock\/table\/([a-z_]+)$/);
        if (t && state.tables[t[1]]) return send(res, 200, state.tables[t[1]]);
        const r = url.pathname.match(/^\/__mock\/table\/([a-z_]+)\/([^/]+)$/);
        if (r && req.method === 'PATCH' && state.tables[r[1]]) {
            const target = state.tables[r[1]].find((x) => x[SCHEMA[r[1]].pk] === decodeURIComponent(r[2]));
            if (!target) return send(res, 404, { error: 'row not found' });
            const before = snapshot(r[1]);
            Object.assign(target, body);
            emitChanges(r[1], before);
            return send(res, 200, target);
        }
        return send(res, 404, { error: 'unknown mock endpoint' });
    }

    requestUserId = state.sessions.get(bearer(req)) ?? null;

    const entry = {
        method: req.method,
        path: url.pathname,
        query: url.search.replace(/^\?/, ''),
        prefer: req.headers.prefer ?? null,
        body: body ?? null,
        status: 0,
    };
    requestLog.push(entry);
    const origWriteHead = res.writeHead.bind(res);
    res.writeHead = (status, ...rest) => {
        entry.status = status;
        return origWriteHead(status, ...rest);
    };

    try {
        if (url.pathname.startsWith('/auth/v1/')) return await handleAuth(req, res, url, body);
        if (url.pathname.startsWith('/rest/v1/')) {
            const m = url.pathname.match(/^\/rest\/v1\/([a-z_]+)$/);
            const table = m && SCHEMA[m[1]] ? m[1] : null;
            if (!table || req.method === 'GET' || req.method === 'HEAD') {
                return handleRest(req, res, url, body);
            }
            const before = snapshot(table);
            const result = handleRest(req, res, url, body);
            emitChanges(table, before);
            return result;
        }
        return send(res, 404, { message: `Mock: unknown path ${url.pathname}` });
    } catch (error) {
        if (error instanceof RestError) return pgError(res, error.status, error.code, error.message);
        console.error('[mock-supabase]', error);
        return pgError(res, 500, 'XX000', String(error));
    }
});

server.on('upgrade', handleUpgrade);

server.listen(PORT, HOST, () => {
    console.log(`[mock-supabase] listening on http://${HOST}:${PORT}`);
});

for (const sig of ['SIGINT', 'SIGTERM']) process.on(sig, () => server.close(() => process.exit(0)));
