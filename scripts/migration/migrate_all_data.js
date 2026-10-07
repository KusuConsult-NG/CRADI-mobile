const { initializeApp, cert } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore } = require('firebase-admin/firestore');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const SUPABASE_URL = process.env.SUPABASE_URL || 'https://splfkqazwzybityoqmyv.supabase.co';
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNwbGZrcWF6d3p5Yml0eW9xbXl2Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc5MDM2ODkzNywiZXhwIjoyMTA1OTQ0OTM3fQ.5rBtyeAjfRdVkahTNroTIY9jFAe0909ef_yGbZMtBqc';

const serviceAccountPath = path.join(__dirname, '../serviceAccountKey.json');
if (!fs.existsSync(serviceAccountPath)) {
  console.error('Service account key not found at', serviceAccountPath);
  process.exit(1);
}

const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, 'utf8'));
const app = initializeApp({ credential: cert(serviceAccount) });
const auth = getAuth(app);
const db = getFirestore(app);

function toUuid(str) {
  const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[4][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  if (uuidRegex.test(str)) return str;
  const hash = crypto.createHash('sha256').update('cradi_' + str).digest('hex');
  return [
    hash.substring(0, 8),
    hash.substring(8, 12),
    '4' + hash.substring(13, 16),
    ((parseInt(hash.substring(16, 18), 16) & 0x3f) | 0x80).toString(16).padStart(2, '0') + hash.substring(18, 20),
    hash.substring(20, 32)
  ].join('-');
}

function parseDate(val) {
  if (!val) return new Date().toISOString();
  if (typeof val === 'string') {
    const d = new Date(val);
    return isNaN(d.getTime()) ? new Date().toISOString() : d.toISOString();
  }
  if (val._seconds) return new Date(val._seconds * 1000).toISOString();
  if (val.toDate && typeof val.toDate === 'function') return val.toDate().toISOString();
  return new Date().toISOString();
}

function normalizeSeverity(sev) {
  if (!sev) return 'medium';
  const s = sev.toLowerCase().trim();
  if (s.includes('crit')) return 'critical';
  if (s.includes('high')) return 'high';
  if (s.includes('low')) return 'low';
  return 'medium';
}

function normalizeStatus(st) {
  if (!st) return 'pending';
  const s = st.toLowerCase().trim();
  if (s.includes('valid')) return 'validated';
  if (s.includes('verif')) return 'verified';
  if (s.includes('resolv')) return 'resolved';
  if (s.includes('reject')) return 'rejected';
  return 'pending';
}

async function supabaseFetch(endpoint, options = {}) {
  const url = `${SUPABASE_URL}${endpoint}`;
  const headers = {
    'apikey': SUPABASE_SERVICE_ROLE_KEY,
    'Authorization': `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
    'Content-Type': 'application/json',
    ...(options.headers || {})
  };

  const res = await fetch(url, { ...options, headers });
  const text = await res.text();
  let data;
  try {
    data = text ? JSON.parse(text) : {};
  } catch (e) {
    data = { raw: text };
  }
  return { ok: res.ok, status: res.status, data };
}

async function runMigration() {
  console.log('====================================================');
  console.log('🚀 CRADI: Starting Firebase -> Supabase Migration');
  console.log('====================================================\n');

  // Step 1: Fetch all Firebase Auth Users
  console.log('📦 1. Fetching Firebase Auth users...');
  let firebaseAuthUsers = [];
  let pageToken;
  do {
    const list = await auth.listUsers(1000, pageToken);
    firebaseAuthUsers.push(...list.users);
    pageToken = list.pageToken;
  } while (pageToken);
  console.log(`   Found ${firebaseAuthUsers.length} users in Firebase Auth.\n`);

  // Step 2: Fetch all Firestore User Profiles
  console.log('📦 2. Fetching Firestore user profiles...');
  const firestoreUsersSnap = await db.collection('users').get();
  const firestoreUsers = new Map();
  firestoreUsersSnap.forEach(doc => {
    firestoreUsers.set(doc.id, doc.data());
  });
  console.log(`   Found ${firestoreUsers.size} user profiles in Firestore.\n`);

  // Step 3: Fetch existing Supabase Auth users to avoid duplicates
  console.log('📦 3. Checking existing Supabase Auth users...');
  const existingUsersRes = await supabaseFetch('/auth/v1/admin/users?per_page=1000');
  const existingEmails = new Set();
  const existingIds = new Set();
  if (existingUsersRes.ok && Array.isArray(existingUsersRes.data?.users)) {
    existingUsersRes.data.users.forEach(u => {
      if (u.email) existingEmails.add(u.email.toLowerCase());
      if (u.id) existingIds.add(u.id);
    });
  }
  console.log(`   Found ${existingEmails.size} existing users in Supabase.\n`);

  // Step 4: Migrate Auth Users to Supabase
  console.log('🔄 4. Migrating Users to Supabase Auth & Profiles...');
  const uidMap = new Map(); // firebaseUid -> supabaseUuid
  let authSuccessCount = 0;
  let authSkippedCount = 0;
  let profileSuccessCount = 0;

  // Process all Firebase Auth users first
  for (const fbUser of firebaseAuthUsers) {
    const targetUuid = toUuid(fbUser.uid);
    uidMap.set(fbUser.uid, targetUuid);

    const email = fbUser.email ? fbUser.email.toLowerCase().trim() : null;
    const fsProfile = firestoreUsers.get(fbUser.uid) || {};

    let userUuid = targetUuid;

    // Check if user already exists in Supabase
    if (email && existingEmails.has(email)) {
      authSkippedCount++;
    } else {
      try {
        const createPayload = {
          id: targetUuid,
          email: email || `${fbUser.uid.toLowerCase()}@migrated.phone`,
          email_confirm: true,
          user_metadata: {
            name: fbUser.displayName || fsProfile.name || 'User',
            full_name: fbUser.displayName || fsProfile.name || 'User',
            legacy_firebase_uid: fbUser.uid
          }
        };
        if (fbUser.phoneNumber) {
          createPayload.phone = fbUser.phoneNumber;
          createPayload.phone_confirm = true;
        }

        const createRes = await supabaseFetch('/auth/v1/admin/users', {
          method: 'POST',
          body: JSON.stringify(createPayload)
        });

        if (createRes.ok) {
          authSuccessCount++;
          if (email) existingEmails.add(email);
        } else {
          // If error is duplicate email or id, mark skipped
          authSkippedCount++;
        }
      } catch (err) {
        console.error(`   Error creating auth user ${email || fbUser.uid}:`, err.message);
      }
    }

    // Now upsert into public.profiles
    const name = fsProfile.name || fbUser.displayName || 'User';
    const profilePayload = {
      id: userUuid,
      email: email || `${fbUser.uid.toLowerCase()}@migrated.phone`,
      name: name,
      full_name: name,
      phone: fsProfile.phone || fbUser.phoneNumber || null,
      role: fsProfile.role || 'user',
      address: fsProfile.address || null,
      state: fsProfile.state || null,
      lga: fsProfile.lga || null,
      ward: fsProfile.ward || null,
      is_approved: fsProfile.isApproved !== undefined ? fsProfile.isApproved : true,
      is_verified: fsProfile.isVerified !== undefined ? fsProfile.isVerified : true,
      is_active: true,
      legacy_firebase_uid: fbUser.uid,
      created_at: parseDate(fsProfile.createdAt || fbUser.metadata?.creationTime),
      updated_at: parseDate(fsProfile.updatedAt)
    };

    const profileRes = await supabaseFetch('/rest/v1/profiles', {
      method: 'POST',
      headers: { 'Prefer': 'resolution=merge-duplicates' },
      body: JSON.stringify(profilePayload)
    });

    if (profileRes.ok) {
      profileSuccessCount++;
    } else {
      console.warn(`   Warning upserting profile ${userUuid}:`, profileRes.data?.message || profileRes.status);
    }
  }

  // Also process any Firestore profiles whose Auth user wasn't in the list
  for (const [fbUid, fsProfile] of firestoreUsers.entries()) {
    if (!uidMap.has(fbUid)) {
      const targetUuid = toUuid(fbUid);
      uidMap.set(fbUid, targetUuid);

      const email = fsProfile.email ? fsProfile.email.toLowerCase().trim() : `${fbUid.toLowerCase()}@migrated.phone`;
      const name = fsProfile.name || 'User';

      if (!existingEmails.has(email)) {
        await supabaseFetch('/auth/v1/admin/users', {
          method: 'POST',
          body: JSON.stringify({
            id: targetUuid,
            email: email,
            email_confirm: true,
            user_metadata: { name, full_name: name, legacy_firebase_uid: fbUid }
          })
        });
        existingEmails.add(email);
        authSuccessCount++;
      }

      await supabaseFetch('/rest/v1/profiles', {
        method: 'POST',
        headers: { 'Prefer': 'resolution=merge-duplicates' },
        body: JSON.stringify({
          id: targetUuid,
          email: email,
          name: name,
          full_name: name,
          phone: fsProfile.phone || null,
          role: fsProfile.role || 'user',
          address: fsProfile.address || null,
          state: fsProfile.state || null,
          lga: fsProfile.lga || null,
          ward: fsProfile.ward || null,
          is_approved: fsProfile.isApproved !== undefined ? fsProfile.isApproved : true,
          is_verified: fsProfile.isVerified !== undefined ? fsProfile.isVerified : true,
          is_active: true,
          legacy_firebase_uid: fbUid,
          created_at: parseDate(fsProfile.createdAt),
          updated_at: parseDate(fsProfile.updatedAt)
        })
      });
      profileSuccessCount++;
    }
  }

  console.log(`   ✅ Auth users: ${authSuccessCount} created, ${authSkippedCount} existing.`);
  console.log(`   ✅ Profiles: ${profileSuccessCount} upserted.\n`);

  // Step 5: Migrate Reports
  console.log('📦 5. Fetching Firestore Reports...');
  const reportsSnap = await db.collection('reports').get();
  console.log(`   Found ${reportsSnap.size} reports. Migrating to Supabase...`);

  let reportsSuccessCount = 0;
  let reportsErrorCount = 0;

  for (const doc of reportsSnap.docs) {
    const raw = doc.data();
    const targetReportId = toUuid(doc.id);
    const mappedUserId = raw.userId ? uidMap.get(raw.userId) || toUuid(raw.userId) : null;

    const reportPayload = {
      id: targetReportId,
      user_id: mappedUserId,
      hazard_type: raw.hazardType || 'Unknown',
      severity: normalizeSeverity(raw.severity),
      status: normalizeStatus(raw.status),
      state: raw.state || null,
      lga: raw.lga || null,
      ward: raw.ward || null,
      community: raw.community || null,
      latitude: typeof raw.latitude === 'number' ? raw.latitude : null,
      longitude: typeof raw.longitude === 'number' ? raw.longitude : null,
      location_details: raw.locationDetails || raw.location || raw.address || null,
      location_description: raw.locationDetails || raw.location || raw.address || null,
      address: raw.address || null,
      description: raw.description || '',
      image_urls: Array.isArray(raw.imageUrls) ? raw.imageUrls : [],
      verification_count: typeof raw.verificationCount === 'number' ? raw.verificationCount : 0,
      is_alert: raw.isAlert || false,
      escalated: raw.escalated || false,
      escalation_reason: raw.escalationReason || null,
      legacy_firebase_id: doc.id,
      submitted_at: parseDate(raw.submittedAt || raw.createdAt),
      created_at: parseDate(raw.createdAt)
    };

    const res = await supabaseFetch('/rest/v1/reports', {
      method: 'POST',
      headers: { 'Prefer': 'resolution=merge-duplicates' },
      body: JSON.stringify(reportPayload)
    });

    if (res.ok) {
      reportsSuccessCount++;
    } else {
      reportsErrorCount++;
      console.warn(`   Warning importing report ${doc.id}:`, res.data?.message || res.status);
    }
  }

  console.log(`   ✅ Reports: ${reportsSuccessCount} imported successfully (${reportsErrorCount} errors).\n`);

  console.log('====================================================');
  console.log('🎉 Migration Completed Successfully!');
  console.log(`   • Total Users in Supabase:   ${profileSuccessCount}`);
  console.log(`   • Total Reports in Supabase: ${reportsSuccessCount}`);
  console.log('====================================================\n');
}

runMigration().catch(err => {
  console.error('Fatal Migration Error:', err);
  process.exit(1);
});
