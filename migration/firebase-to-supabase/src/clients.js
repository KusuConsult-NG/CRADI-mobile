// Environment loading and SDK clients. Kept separate from migrate.js so the
// runner reads top to bottom as the migration steps.

import fs from 'node:fs';
import path from 'node:path';
import { initializeApp, cert, applicationDefault } from 'firebase-admin/app';
import { getFirestore, FieldPath } from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';
import { getStorage } from 'firebase-admin/storage';
import { createClient } from '@supabase/supabase-js';

export function loadDotEnv(dir) {
  const file = path.join(dir, '.env');
  if (fs.existsSync(file)) process.loadEnvFile(file);
}

export function firebaseClients(env = process.env) {
  const projectId = env.FIREBASE_PROJECT_ID || 'ewer-8f788';
  const storageBucket = env.FIREBASE_STORAGE_BUCKET || `${projectId}.firebasestorage.app`;
  let credential;
  const sa = env.FIREBASE_SERVICE_ACCOUNT?.trim();
  if (sa) {
    const json = sa.startsWith('{') ? JSON.parse(sa) : JSON.parse(fs.readFileSync(path.resolve(sa), 'utf8'));
    credential = cert(json);
  } else if (env.GOOGLE_APPLICATION_CREDENTIALS) {
    credential = applicationDefault();
  } else {
    throw new Error(
      'Set FIREBASE_SERVICE_ACCOUNT (path or JSON) or GOOGLE_APPLICATION_CREDENTIALS to a service-account key for ' +
        projectId,
    );
  }
  const app = initializeApp({ credential, projectId, storageBucket }, 'migration');
  return {
    projectId,
    db: getFirestore(app),
    auth: getAuth(app),
    bucket: getStorage(app).bucket(storageBucket),
  };
}

export function supabaseClient(env = process.env, { required }) {
  const url = env.SUPABASE_URL?.trim();
  const key = env.SUPABASE_SERVICE_ROLE_KEY?.trim();
  if (!url || !key) {
    if (required) throw new Error('SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required with --apply');
    return null;
  }
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
}

/** Read a whole Firestore collection, paginated by document id. */
export async function readCollection(db, name, pageSize = 500) {
  const docs = [];
  let last = null;
  for (;;) {
    let query = db.collection(name).orderBy(FieldPath.documentId()).limit(pageSize);
    if (last) query = query.startAfter(last);
    const snap = await query.get();
    for (const doc of snap.docs) docs.push({ id: doc.id, data: doc.data() });
    if (snap.size < pageSize) break;
    last = snap.docs[snap.docs.length - 1];
  }
  return docs;
}

export async function listFirebaseAuthUsers(auth) {
  const users = [];
  let pageToken;
  do {
    const page = await auth.listUsers(1000, pageToken);
    users.push(...page.users.map((u) => u.toJSON()));
    pageToken = page.pageToken;
  } while (pageToken);
  return users;
}
