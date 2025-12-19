const sdk = require('node-appwrite');

// Configuration
const ENDPOINT = 'https://fra.cloud.appwrite.io/v1';
const PROJECT_ID = '6941cdb400050e7249d5';
const DATABASE_ID = '6941e2c2003705bb5a25'; // Actual database ID from Appwrite

// You need to get this from: https://cloud.appwrite.io/console/project-6941cdb400050e7249d5/auth/apikeys
// Create an API key with full permissions (Database, Storage permissions)
const API_KEY = process.env.APPWRITE_API_KEY || 'YOUR_API_KEY_HERE';

if (API_KEY === 'YOUR_API_KEY_HERE') {
    console.error('❌ Error: Please set your Appwrite API key');
    console.error('   Get it from: https://cloud.appwrite.io/console/project-6941cdb400050e7249d5/auth/apikeys');
    console.error('   Then run: APPWRITE_API_KEY=your_key node setup_appwrite.js');
    process.exit(1);
}

// Initialize Appwrite client
const client = new sdk.Client()
    .setEndpoint(ENDPOINT)
    .setProject(PROJECT_ID)
    .setKey(API_KEY);

const databases = new sdk.Databases(client);
const storage = new sdk.Storage(client);

async function createDatabase() {
    // Database already exists, skipping creation
    console.log('📦 Using existing database: ' + DATABASE_ID);
    return;
    /*
    try {
        console.log('📦 Creating database...');
        await databases.create(DATABASE_ID, 'CRADI Database');
        console.log('✅ Database created: ' + DATABASE_ID);
    } catch (error) {
        if (error.code === 409) {
            console.log('ℹ️  Database already exists: ' + DATABASE_ID);
        } else {
            throw error;
        }
    }
    */
}

async function createUsersCollection() {
    try {
        console.log('\\n👥 Creating users collection...');
        await databases.createCollection(DATABASE_ID, 'users', 'Users');

        // Create attributes
        await databases.createStringAttribute(DATABASE_ID, 'users', 'email', 255, true);
        await databases.createStringAttribute(DATABASE_ID, 'users', 'name', 255, true);
        await databases.createStringAttribute(DATABASE_ID, 'users', 'role', 50, true, 'ewm');
        await databases.createStringAttribute(DATABASE_ID, 'users', 'phoneNumber', 20, false);
        await databases.createStringAttribute(DATABASE_ID, 'users', 'profileImageId', 255, false);
        await databases.createStringAttribute(DATABASE_ID, 'users', 'registrationCode', 20, false);
        await databases.createBooleanAttribute(DATABASE_ID, 'users', 'biometricsEnabled', false, false);
        await databases.createDatetimeAttribute(DATABASE_ID, 'users', 'createdAt', true);
        await databases.createDatetimeAttribute(DATABASE_ID, 'users', 'lastLoginAt', false);

        console.log('   ✅ Attributes created');

        // Create indexes
        await databases.createIndex(DATABASE_ID, 'users', 'email_idx', 'unique', ['email']);
        await databases.createIndex(DATABASE_ID, 'users', 'registrationCode_idx', 'unique', ['registrationCode']);
        await databases.createIndex(DATABASE_ID, 'users', 'role_idx', 'key', ['role']);

        console.log('   ✅ Indexes created');
        console.log('✅ Users collection created');
    } catch (error) {
        if (error.code === 409) {
            console.log('ℹ️  Users collection already exists');
        } else {
            throw error;
        }
    }
}

async function createReportsCollection() {
    try {
        console.log('\\n📋 Creating reports collection...');
        await databases.createCollection(DATABASE_ID, 'reports', 'Reports');

        // Create attributes
        await databases.createStringAttribute(DATABASE_ID, 'reports', 'userId', 255, true);
        await databases.createStringAttribute(DATABASE_ID, 'reports', 'hazardType', 100, true);
        await databases.createStringAttribute(DATABASE_ID, 'reports', 'severity', 50, true);
        await databases.createFloatAttribute(DATABASE_ID, 'reports', 'latitude', true);
        await databases.createFloatAttribute(DATABASE_ID, 'reports', 'longitude', true);
        await databases.createStringAttribute(DATABASE_ID, 'reports', 'locationDetails', 500, true);
        await databases.createStringAttribute(DATABASE_ID, 'reports', 'description', 2000, false);
        await databases.createStringAttribute(DATABASE_ID, 'reports', 'imageIds', 255, false, undefined, true);
        await databases.createStringAttribute(DATABASE_ID, 'reports', 'status', 50, true, 'pending');
        await databases.createBooleanAttribute(DATABASE_ID, 'reports', 'isAlert', false, false);
        await databases.createDatetimeAttribute(DATABASE_ID, 'reports', 'submittedAt', true);
        await databases.createIntegerAttribute(DATABASE_ID, 'reports', 'verificationCount', false, 0);

        console.log('   ✅ Attributes created');

        // Create indexes
        await databases.createIndex(DATABASE_ID, 'reports', 'userId_idx', 'key', ['userId']);
        await databases.createIndex(DATABASE_ID, 'reports', 'status_idx', 'key', ['status']);
        await databases.createIndex(DATABASE_ID, 'reports', 'isAlert_idx', 'key', ['isAlert']);
        await databases.createIndex(DATABASE_ID, 'reports', 'submittedAt_idx', 'key', ['submittedAt'], ['DESC']);

        console.log('   ✅ Indexes created');
        console.log('✅ Reports collection created');
    } catch (error) {
        if (error.code === 409) {
            console.log('ℹ️  Reports collection already exists');
        } else {
            throw error;
        }
    }
}

async function createMessagesCollection() {
    try {
        console.log('\\n💬 Creating messages collection...');
        await databases.createCollection(DATABASE_ID, 'messages', 'Messages');

        // Create attributes
        await databases.createStringAttribute(DATABASE_ID, 'messages', 'chatId', 255, true);
        await databases.createStringAttribute(DATABASE_ID, 'messages', 'senderId', 255, true);
        await databases.createStringAttribute(DATABASE_ID, 'messages', 'senderName', 255, true);
        await databases.createStringAttribute(DATABASE_ID, 'messages', 'message', 5000, true);
        await databases.createStringAttribute(DATABASE_ID, 'messages', 'type', 50, true, 'text');
        await databases.createDatetimeAttribute(DATABASE_ID, 'messages', 'sentAt', true);
        await databases.createBooleanAttribute(DATABASE_ID, 'messages', 'read', false, false);

        console.log('   ✅ Attributes created');

        // Create indexes
        await databases.createIndex(DATABASE_ID, 'messages', 'chatId_idx', 'key', ['chatId']);
        await databases.createIndex(DATABASE_ID, 'messages', 'sentAt_idx', 'key', ['sentAt'], ['DESC']);

        console.log('   ✅ Indexes created');
        console.log('✅ Messages collection created');
    } catch (error) {
        if (error.code === 409) {
            console.log('ℹ️  Messages collection already exists');
        } else {
            throw error;
        }
    }
}

async function createEmergencyContactsCollection() {
    try {
        console.log('\\n🚨 Creating emergency_contacts collection...');
        await databases.createCollection(DATABASE_ID, 'emergency_contacts', 'Emergency Contacts');

        // Create attributes
        await databases.createStringAttribute(DATABASE_ID, 'emergency_contacts', 'userId', 255, true);
        await databases.createStringAttribute(DATABASE_ID, 'emergency_contacts', 'name', 255, true);
        await databases.createStringAttribute(DATABASE_ID, 'emergency_contacts', 'phone', 20, true);
        await databases.createStringAttribute(DATABASE_ID, 'emergency_contacts', 'relationship', 100, false);
        await databases.createDatetimeAttribute(DATABASE_ID, 'emergency_contacts', 'createdAt', true);

        console.log('   ✅ Attributes created');

        // Create indexes
        await databases.createIndex(DATABASE_ID, 'emergency_contacts', 'userId_idx', 'key', ['userId']);

        console.log('   ✅ Indexes created');
        console.log('✅ Emergency contacts collection created');
    } catch (error) {
        if (error.code === 409) {
            console.log('ℹ️  Emergency contacts collection already exists');
        } else {
            throw error;
        }
    }
}

async function createProfileImagesBucket() {
    try {
        console.log('\\n🖼️  Creating profile_images bucket...');
        await storage.createBucket(
            'profile_images',
            'Profile Images',
            ['read("any")'],
            ['create("users")', 'update("users")', 'delete("users")'],
            false,
            undefined,
            undefined,
            ['jpg', 'jpeg', 'png', 'webp'],
            5 * 1024 * 1024, // 5MB
            true,
            true
        );
        console.log('✅ Profile images bucket created');
    } catch (error) {
        if (error.code === 409) {
            console.log('ℹ️  Profile images bucket already exists');
        } else {
            throw error;
        }
    }
}

async function createReportImagesBucket() {
    try {
        console.log('\\n📸 Creating report_images bucket...');
        await storage.createBucket(
            'report_images',
            'Report Images',
            ['read("any")'],
            ['create("users")', 'update("users")', 'delete("users")'],
            false,
            undefined,
            undefined,
            ['jpg', 'jpeg', 'png', 'webp'],
            10 * 1024 * 1024, // 10MB
            true,
            true
        );
        console.log('✅ Report images bucket created');
    } catch (error) {
        if (error.code === 409) {
            console.log('ℹ️  Report images bucket already exists');
        } else {
            throw error;
        }
    }
}

async function setupAppwrite() {
    try {
        console.log('🚀 Starting Appwrite setup for CRADI Mobile\\n');
        console.log(`📡 Endpoint: ${ENDPOINT}`);
        console.log(`🆔 Project: ${PROJECT_ID}\\n`);

        await createDatabase();
        await createUsersCollection();
        await createReportsCollection();
        await createMessagesCollection();
        await createEmergencyContactsCollection();

        // Skip bucket creation - already exists or limit reached
        console.log('\\n📦 Skipping storage bucket creation (limit reached or already exist)');
        // await createProfileImagesBucket();
        // await createReportImagesBucket();

        console.log('\\n🎉 Appwrite setup complete!');
        console.log('\\n📋 Summary:');
        console.log('   ✅ Database: 6941e2c2003705bb5a25');
        console.log('   ✅ Collections: 4');
        console.log('   ℹ️  Storage buckets: Using existing');
        console.log('\\n⚠️  Remember to:');
        console.log('   1. Configure SMS provider for phone OTP in Appwrite Console');
        console.log('   2. Run verification script: node verify_appwrite_setup.js');
        console.log('   3. Test authentication flows in the app');

        process.exit(0);
    } catch (error) {
        console.error('\\n❌ Setup failed:', error.message);
        if (error.response) {
            console.error('   Response:', error.response);
        }
        process.exit(1);
    }
}

setupAppwrite();
