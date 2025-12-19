const sdk = require('node-appwrite');

// Configuration
const ENDPOINT = 'https://fra.cloud.appwrite.io/v1';
const PROJECT_ID = '6941cdb400050e7249d5';
const DATABASE_ID = '6941e2c2003705bb5a25'; // Actual database ID from Appwrite

// Get API key from environment
const API_KEY = process.env.APPWRITE_API_KEY || '';

if (!API_KEY || API_KEY === 'YOUR_API_KEY_HERE') {
    console.error('❌ Error: Please set your Appwrite API key');
    console.error('   Get it from: https://cloud.appwrite.io/console/project-6941cdb400050e7249d5/auth/apikeys');
    console.error('   Then run: APPWRITE_API_KEY=your_key node verify_appwrite_setup.js');
    process.exit(1);
}

// Initialize Appwrite client
const client = new sdk.Client()
    .setEndpoint(ENDPOINT)
    .setProject(PROJECT_ID)
    .setKey(API_KEY);

const databases = new sdk.Databases(client);
const storage = new sdk.Storage(client);

let passedChecks = 0;
let failedChecks = 0;

function logSuccess(message) {
    console.log(`✅ ${message}`);
    passedChecks++;
}

function logFailure(message) {
    console.log(`❌ ${message}`);
    failedChecks++;
}

function logInfo(message) {
    console.log(`ℹ️  ${message}`);
}

async function verifyDatabase() {
    try {
        console.log('\\n📦 Verifying database...');
        const database = await databases.get(DATABASE_ID);
        logSuccess(`Database exists: ${database.name} (ID: ${database.$id})`);
        return true;
    } catch (error) {
        logFailure('Database not found: ' + DATABASE_ID);
        return false;
    }
}

async function verifyCollection(collectionId, expectedAttributes, expectedIndexes) {
    try {
        const collection = await databases.getCollection(DATABASE_ID, collectionId);
        logSuccess(`Collection exists: ${collection.name} (ID: ${collectionId})`);

        // Verify attributes
        const actualAttributes = collection.attributes.map(attr => attr.key);
        const missingAttributes = expectedAttributes.filter(attr => !actualAttributes.includes(attr));

        if (missingAttributes.length > 0) {
            logFailure(`  Missing attributes in ${collectionId}: ${missingAttributes.join(', ')}`);
        } else {
            logInfo(`  All ${expectedAttributes.length} attributes present`);
        }

        // Verify indexes
        const actualIndexes = collection.indexes.map(idx => idx.key);
        const missingIndexes = expectedIndexes.filter(idx => {
            return !actualIndexes.some(actual => actual.includes(idx));
        });

        if (missingIndexes.length > 0) {
            logFailure(`  Missing indexes in ${collectionId}: ${missingIndexes.join(', ')}`);
        } else {
            logInfo(`  All ${expectedIndexes.length} indexes present`);
        }

        return true;
    } catch (error) {
        logFailure(`Collection not found: ${collectionId}`);
        return false;
    }
}

async function verifyBucket(bucketId) {
    try {
        const bucket = await storage.getBucket(bucketId);
        logSuccess(`Storage bucket exists: ${bucket.name} (ID: ${bucketId})`);
        logInfo(`  Max file size: ${bucket.maximumFileSize / 1024 / 1024}MB`);
        logInfo(`  Allowed extensions: ${bucket.allowedFileExtensions.join(', ')}`);
        return true;
    } catch (error) {
        logFailure(`Storage bucket not found: ${bucketId}`);
        return false;
    }
}

async function verifyAppwriteSetup() {
    try {
        console.log('🔍 Verifying Appwrite setup for CRADI Mobile\\n');
        console.log(`📡 Endpoint: ${ENDPOINT}`);
        console.log(`🆔 Project: ${PROJECT_ID}`);

        // Verify database
        const dbExists = await verifyDatabase();

        if (!dbExists) {
            console.log('\\n❌ Database does not exist. Run setup_appwrite.js first.');
            process.exit(1);
        }

        // Verify collections
        console.log('\\n👥 Verifying users collection...');
        await verifyCollection(
            'users',
            ['email', 'name', 'role', 'phoneNumber', 'profileImageId', 'registrationCode', 'biometricsEnabled', 'createdAt', 'lastLoginAt'],
            ['email', 'registrationCode', 'role']
        );

        console.log('\\n📋 Verifying reports collection...');
        await verifyCollection(
            'reports',
            ['userId', 'hazardType', 'severity', 'latitude', 'longitude', 'locationDetails', 'description', 'imageIds', 'status', 'isAlert', 'submittedAt', 'verificationCount'],
            ['userId', 'status', 'isAlert', 'submittedAt']
        );

        console.log('\\n💬 Verifying messages collection...');
        await verifyCollection(
            'messages',
            ['chatId', 'senderId', 'senderName', 'message', 'type', 'sentAt', 'read'],
            ['chatId', 'sentAt']
        );

        console.log('\\n🚨 Verifying emergency_contacts collection...');
        await verifyCollection(
            'emergency_contacts',
            ['userId', 'name', 'phone', 'relationship', 'createdAt'],
            ['userId']
        );

        // Verify storage buckets
        console.log('\\n🖼️  Verifying profile_images bucket...');
        await verifyBucket('profile_images');

        console.log('\\n📸 Verifying report_images bucket...');
        await verifyBucket('report_images');

        // Summary
        console.log('\\n📊 Verification Summary:');
        console.log(`   ✅ Passed: ${passedChecks}`);
        console.log(`   ❌ Failed: ${failedChecks}`);

        if (failedChecks === 0) {
            console.log('\\n🎉 All checks passed! Appwrite setup is complete.');
            console.log('\\n📱 Next steps:');
            console.log('   1. Configure SMS provider in Appwrite Console for phone OTP');
            console.log('   2. Test authentication flows in the Flutter app');
            console.log('   3. Try uploading a profile image');
            process.exit(0);
        } else {
            console.log('\\n⚠️  Some checks failed. Please review and fix the issues.');
            console.log('   Run: node setup_appwrite.js to create missing resources');
            process.exit(1);
        }

    } catch (error) {
        console.error('\\n❌ Verification failed:', error.message);
        if (error.response) {
            console.error('   Response:', error.response);
        }
        process.exit(1);
    }
}

verifyAppwriteSetup();
