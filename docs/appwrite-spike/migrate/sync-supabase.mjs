#!/usr/bin/env node
import { readFileSync } from 'node:fs';
import pg from 'pg';

import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = resolve(HERE, '../../..');

const SUPABASE_URL = process.env.SUPABASE_URL || 'https://splfkqazwzybityoqmyv.supabase.co';
const SERVICE_KEY =
  process.env.SUPABASE_SERVICE_ROLE_KEY ||
  readFileSync(resolve(REPO, '.env.production'), 'utf8')
    .split('\n')
    .find((l) => l.startsWith('SUPABASE_SERVICE_ROLE_KEY='))
    .split('=')[1]
    .trim();

const PG_URL = process.env.PG_URL || 'postgres://postgres:postgres@localhost:5432/cradi_mig';

const client = new pg.Client({ connectionString: PG_URL });
await client.connect();

console.log('Connected to local PostgreSQL:', PG_URL);

async function fetchRest(table) {
  let all = [];
  let offset = 0;
  const limit = 1000;
  while (true) {
    const res = await fetch(`${SUPABASE_URL}/rest/v1/${table}?select=*&limit=${limit}&offset=${offset}`, {
      headers: {
        apikey: SERVICE_KEY,
        Authorization: `Bearer ${SERVICE_KEY}`,
      },
    });
    if (!res.ok) {
      if (res.status === 404) return [];
      throw new Error(`Failed to fetch ${table}: ${res.status} ${await res.text()}`);
    }
    const rows = await res.json();
    all.push(...rows);
    if (rows.length < limit) break;
    offset += limit;
  }
  return all;
}

async function fetchAuthUsers() {
  let all = [];
  let page = 1;
  while (true) {
    const res = await fetch(`${SUPABASE_URL}/auth/v1/admin/users?page=${page}&per_page=500`, {
      headers: {
        apikey: SERVICE_KEY,
        Authorization: `Bearer ${SERVICE_KEY}`,
      },
    });
    if (!res.ok) throw new Error(`Failed to fetch auth users: ${res.status}`);
    const data = await res.json();
    const users = data.users || [];
    all.push(...users);
    if (users.length < 500) break;
    page++;
  }
  return all;
}

await client.query("SET session_replication_role = 'replica';");

try {
  // 1. auth.users
  console.log('Fetching auth.users from Supabase...');
  const users = await fetchAuthUsers();
  console.log(`Fetched ${users.length} auth.users`);
  for (const u of users) {
    await client.query(
      `INSERT INTO auth.users (id, email, phone, raw_user_meta_data, email_confirmed_at, phone_confirmed_at)
       VALUES ($1, $2, $3, $4, $5, $6)
       ON CONFLICT (id) DO UPDATE SET
         email = EXCLUDED.email, phone = EXCLUDED.phone,
         raw_user_meta_data = EXCLUDED.raw_user_meta_data,
         email_confirmed_at = EXCLUDED.email_confirmed_at,
         phone_confirmed_at = EXCLUDED.phone_confirmed_at`,
      [
        u.id,
        u.email ?? null,
        u.phone ?? null,
        JSON.stringify(u.user_metadata ?? {}),
        u.email_confirmed_at ?? null,
        u.phone_confirmed_at ?? null,
      ],
    );
  }

  // 2. public tables
  const tables = [
    'profiles',
    'reports',
    'verifications',
    'verification_overrides',
    'authorities',
    'alerts',
    'contacts',
    'messages',
    'trusted_devices',
    'login_history',
    'ndpa_consents',
    'knowledge_base',
    'news_links',
    'app_settings',
    'scheduled_escalations',
    'notification_outbox',
    'sms_deliveries',
  ];

  for (const tbl of tables) {
    const rows = await fetchRest(tbl);
    console.log(`Fetched ${rows.length} rows for ${tbl}`);
    if (rows.length === 0) continue;

    // Truncate existing local table rows before inserting fresh snapshot
    await client.query(`DELETE FROM public."${tbl}"`);

    // Query columns that actually exist in the target table
    const colInfo = await client.query(
      `SELECT column_name FROM information_schema.columns WHERE table_schema = 'public' AND table_name = $1`,
      [tbl],
    );
    const validCols = new Set(colInfo.rows.map((r) => r.column_name));

    for (const row of rows) {
      const entries = Object.entries(row).filter(([k]) => validCols.has(k));
      const keys = entries.map(([k]) => k);
      const vals = entries.map(([k, v]) => {
        if (tbl === 'app_settings' && k === 'value') return JSON.stringify(v);
        if (Array.isArray(v)) return v;
        if (typeof v === 'object' && v !== null) return JSON.stringify(v);
        return v;
      });
      const cols = keys.map((k) => `"${k}"`).join(', ');
      const placeholders = keys.map((_, i) => `$${i + 1}`).join(', ');

      await client.query(`INSERT INTO public."${tbl}" (${cols}) VALUES (${placeholders})`, vals);
    }
  }

  console.log('All data mirrored successfully into local cradi_mig!');
} finally {
  await client.query("SET session_replication_role = 'origin';");
  await client.end();
}
