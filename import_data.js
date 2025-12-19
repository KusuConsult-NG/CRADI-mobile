const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

// Initialize Firebase Admin
const serviceAccount = require('./serviceAccountKey.json');

admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    projectId: 'cradi-845d6'
});

const db = admin.firestore();

// Load sample data
const sampleDataPath = path.join(__dirname, '../.gemini/antigravity/brain/02c498f4-b5b7-4c69-8fee-8c481b04eafc/sample_firestore_data.json');
const sampleData = JSON.parse(fs.readFileSync(sampleDataPath, 'utf8'));

// Helper to convert timestamp objects
function convertTimestamps(data) {
    if (data && typeof data === 'object') {
        if (data._seconds !== undefined) {
            // Convert Firestore timestamp format
            return admin.firestore.Timestamp.fromMillis(data._seconds * 1000);
        }

        // Recursively handle nested objects
        const converted = Array.isArray(data) ? [] : {};
        for (const key in data) {
            converted[key] = convertTimestamps(data[key]);
        }
        return converted;
    }
    return data;
}

async function importData() {
    console.log('🚀 Starting Firestore data import...\n');

    let totalDocs = 0;

    for (const [collectionName, documents] of Object.entries(sampleData)) {
        console.log(`📁 Importing collection: ${collectionName}`);

        for (const [docId, docData] of Object.entries(documents)) {
            try {
                // Convert timestamps
                const convertedData = convertTimestamps(docData);

                // Import document
                await db.collection(collectionName).doc(docId).set(convertedData);
                console.log(`  ✅ ${docId}`);
                totalDocs++;
            } catch (error) {
                console.error(`  ❌ Error importing ${docId}:`, error.message);
            }
        }

        console.log(`  📊 ${Object.keys(documents).length} documents imported\n`);
    }

    console.log(`\n🎉 Import complete! Total: ${totalDocs} documents imported`);
    console.log('\n📋 Collections imported:');
    for (const collectionName of Object.keys(sampleData)) {
        const count = Object.keys(sampleData[collectionName]).length;
        console.log(`  - ${collectionName}: ${count} documents`);
    }

    process.exit(0);
}

// Run import
importData().catch((error) => {
    console.error('❌ Import failed:', error);
    process.exit(1);
});
