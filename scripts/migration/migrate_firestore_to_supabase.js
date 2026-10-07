/**
 * Firebase to Supabase Data Migration Tool
 * 
 * Usage:
 *   1. Place your serviceAccountKey.json (from Firebase Console -> Project Settings -> Service Accounts)
 *      in the scripts/migration/ directory.
 *   2. Run: node scripts/migration/migrate_firestore_to_supabase.js
 */

const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { createClient } = require('@supabase/supabase-js');
const fs = require('fs');
const path = require('path');

const SUPABASE_URL = process.env.SUPABASE_URL || 'https://splfkqazwzybityoqmyv.supabase.co';
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNwbGZrcWF6d3p5Yml0eW9xbXl2Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc5MDM2ODkzNywiZXhwIjoyMTA1OTQ0OTM3fQ.5rBtyeAjfRdVkahTNroTIY9jFAe0909ef_yGbZMtBqc';

const serviceAccountPath = path.join(__dirname, 'serviceAccountKey.json');

if (!fs.existsSync(serviceAccountPath)) {
    console.error(`❌ Missing Firebase serviceAccountKey.json in ${serviceAccountPath}`);
    console.error(`Please download it from Firebase Console -> Project Settings -> Service Accounts -> Generate new private key.`);
    process.exit(1);
}

const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, 'utf8'));

initializeApp({
    credential: cert(serviceAccount)
});

const firestore = getFirestore();
const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

async function migrateCollection(collectionName, targetTable, mapFn) {
    console.log(`\n⏳ Migrating Firestore "${collectionName}" -> Supabase "${targetTable}"...`);
    const snapshot = await firestore.collection(collectionName).get();
    
    if (snapshot.empty) {
        console.log(`ℹ️ Collection "${collectionName}" is empty, skipping.`);
        return;
    }

    const records = [];
    snapshot.forEach(doc => {
        const raw = doc.data();
        raw.id = doc.id;
        const mapped = mapFn ? mapFn(raw) : raw;
        records.push(mapped);
    });

    console.log(`Found ${records.length} documents. Inserting into Supabase...`);
    
    // Batch upsert in chunks of 100
    const chunkSize = 100;
    for (let i = 0; i < records.length; i += chunkSize) {
        const chunk = records.slice(i, i + chunkSize);
        const { error } = await supabase.from(targetTable).upsert(chunk);
        if (error) {
            console.error(`❌ Error migrating chunk into ${targetTable}:`, error);
        } else {
            console.log(`✅ Inserted ${i + chunk.length} / ${records.length} records.`);
        }
    }
}

async function run() {
    try {
        console.log("🚀 Starting Firestore to Supabase Migration...");

        // 1. Users / Profiles
        await migrateCollection('users', 'profiles', (data) => ({
            id: data.id,
            email: data.email || null,
            phone_number: data.phoneNumber || data.phone || null,
            full_name: data.fullName || data.name || null,
            role: data.role || 'user',
            state: data.state || null,
            lga: data.lga || null,
            ward: data.ward || null,
            community: data.community || null,
            profile_image_url: data.profileImageUrl || null,
            created_at: data.createdAt ? new Date(data.createdAt._seconds ? data.createdAt._seconds * 1000 : data.createdAt).toISOString() : new Date().toISOString()
        }));

        // 2. Reports
        await migrateCollection('reports', 'reports', (data) => ({
            id: data.id,
            user_id: data.userId || null,
            hazard_type: data.hazardType || 'Unknown',
            severity: data.severity || 'medium',
            status: data.status || 'pending',
            state: data.state || '',
            lga: data.lga || '',
            ward: data.ward || null,
            community: data.community || null,
            latitude: data.latitude || null,
            longitude: data.longitude || null,
            location_description: data.locationDescription || null,
            description: data.description || '',
            image_urls: data.imageUrls || (data.imageUrl ? [data.imageUrl] : []),
            submitted_at: data.submittedAt ? new Date(data.submittedAt._seconds ? data.submittedAt._seconds * 1000 : data.submittedAt).toISOString() : new Date().toISOString()
        }));

        // 3. Emergency Contacts
        await migrateCollection('emergency_contacts', 'emergency_contacts', (data) => ({
            id: data.id,
            user_id: data.userId || null,
            name: data.name || '',
            phone_number: data.phoneNumber || data.phone || '',
            relationship: data.relationship || null,
            agency_or_department: data.agency || null,
            state: data.state || null,
            lga: data.lga || null
        }));

        // 4. Alerts
        await migrateCollection('alerts', 'alerts', (data) => ({
            id: data.id,
            title: data.title || '',
            message: data.message || '',
            hazard_type: data.hazardType || 'General',
            severity: data.severity || 'high',
            target_state: data.state || data.targetState || null,
            target_lga: data.lga || data.targetLga || null,
            target_ward: data.ward || data.targetWard || null,
            is_active: data.isActive !== false
        }));

        console.log("\n🎉 Firestore to Supabase Migration completed successfully!");
    } catch (err) {
        console.error("Fatal migration error:", err);
    }
}

run();
