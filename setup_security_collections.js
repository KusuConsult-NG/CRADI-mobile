const sdk = require('node-appwrite');

// Initialize the Appwrite client
const API_KEY = process.env.APPWRITE_API_KEY || 'YOUR_API_KEY_HERE';

if (API_KEY === 'YOUR_API_KEY_HERE') {
    console.error('❌ Error: Please set your Appwrite API key');
    console.error('   Get it from: https://cloud.appwrite.io/console/project-6941cdb400050e7249d5/auth/apikeys');
    console.error('   Then run: APPWRITE_API_KEY=your_key node setup_security_collections.js');
    process.exit(1);
}

const client = new sdk.Client()
    .setEndpoint('https://cloud.appwrite.io/v1')
    .setProject('6941cdb400050e7249d5')
    .setKey(API_KEY);

const databases = new sdk.Databases(client);

const DATABASE_ID = '6941e2c2003705bb5a25';

async function setupSecurityCollections() {
    console.log('🚀 Setting up security collections...\n');

    try {
        // 1. Create login_history collection
        console.log('📝 Creating login_history collection...');
        const loginHistoryCollection = await databases.createCollection(
            DATABASE_ID,
            'login_history',
            'login_history',
            [
                'read("users")',
                'create("users")',
                'update("users")'
            ],
            true // documentSecurity
        );
        console.log('✅ login_history collection created\n');

        // Add attributes to login_history
        console.log('📝 Adding attributes to login_history...');
        await databases.createStringAttribute(DATABASE_ID, 'login_history', 'userId', 255, true);
        await databases.createBooleanAttribute(DATABASE_ID, 'login_history', 'success', true);
        await databases.createDatetimeAttribute(DATABASE_ID, 'login_history', 'timestamp', true);
        await databases.createStringAttribute(DATABASE_ID, 'login_history', 'deviceFingerprint', 255, true);
        await databases.createStringAttribute(DATABASE_ID, 'login_history', 'deviceName', 255, false);
        await databases.createStringAttribute(DATABASE_ID, 'login_history', 'ipAddress', 45, false);
        await databases.createIntegerAttribute(DATABASE_ID, 'login_history', 'riskScore', false);
        await databases.createStringAttribute(DATABASE_ID, 'login_history', 'riskLevel', 50, false);
        console.log('✅ login_history attributes added\n');

        // Create indexes for login_history
        console.log('📝 Creating indexes for login_history...');
        await databases.createIndex(DATABASE_ID, 'login_history', 'userId_idx', 'key', ['userId']);
        await databases.createIndex(DATABASE_ID, 'login_history', 'timestamp_idx', 'key', ['timestamp']);
        await databases.createIndex(DATABASE_ID, 'login_history', 'success_idx', 'key', ['success']);
        console.log('✅ login_history indexes created\n');

        // 2. Create trusted_devices collection
        console.log('📝 Creating trusted_devices collection...');
        const trustedDevicesCollection = await databases.createCollection(
            DATABASE_ID,
            'trusted_devices',
            'trusted_devices',
            [
                'read("users")',
                'create("users")',
                'update("users")',
                'delete("users")'
            ],
            true // documentSecurity
        );
        console.log('✅ trusted_devices collection created\n');

        // Add attributes to trusted_devices
        console.log('📝 Adding attributes to trusted_devices...');
        await databases.createStringAttribute(DATABASE_ID, 'trusted_devices', 'userId', 255, true);
        await databases.createStringAttribute(DATABASE_ID, 'trusted_devices', 'deviceFingerprint', 255, true);
        await databases.createStringAttribute(DATABASE_ID, 'trusted_devices', 'deviceName', 255, false);
        await databases.createBooleanAttribute(DATABASE_ID, 'trusted_devices', 'trusted', true);
        await databases.createDatetimeAttribute(DATABASE_ID, 'trusted_devices', 'lastUsed', true);
        await databases.createDatetimeAttribute(DATABASE_ID, 'trusted_devices', 'createdAt', true);
        console.log('✅ trusted_devices attributes added\n');

        // Create indexes for trusted_devices
        console.log('📝 Creating indexes for trusted_devices...');
        await databases.createIndex(DATABASE_ID, 'trusted_devices', 'userId_idx', 'key', ['userId']);
        await databases.createIndex(DATABASE_ID, 'trusted_devices', 'deviceFingerprint_idx', 'key', ['deviceFingerprint']);
        await databases.createIndex(DATABASE_ID, 'trusted_devices', 'userId_deviceFingerprint_idx', 'key', ['userId', 'deviceFingerprint']);
        console.log('✅ trusted_devices indexes created\n');

        // 3. Create security_alerts collection
        console.log('📝 Creating security_alerts collection...');
        const securityAlertsCollection = await databases.createCollection(
            DATABASE_ID,
            'security_alerts',
            'security_alerts',
            [
                'read("users")',
                'create("users")',
                'update("users")',
                'delete("users")'
            ],
            true // documentSecurity
        );
        console.log('✅ security_alerts collection created\n');

        // Add attributes to security_alerts
        console.log('📝 Adding attributes to security_alerts...');
        await databases.createStringAttribute(DATABASE_ID, 'security_alerts', 'userId', 255, true);
        await databases.createStringAttribute(DATABASE_ID, 'security_alerts', 'type', 100, true);
        await databases.createStringAttribute(DATABASE_ID, 'security_alerts', 'severity', 50, true);
        await databases.createStringAttribute(DATABASE_ID, 'security_alerts', 'message', 500, true);
        await databases.createBooleanAttribute(DATABASE_ID, 'security_alerts', 'acknowledged', true);
        await databases.createDatetimeAttribute(DATABASE_ID, 'security_alerts', 'timestamp', true);
        console.log('✅ security_alerts attributes added\n');

        // Create indexes for security_alerts
        console.log('📝 Creating indexes for security_alerts...');
        await databases.createIndex(DATABASE_ID, 'security_alerts', 'userId_idx', 'key', ['userId']);
        await databases.createIndex(DATABASE_ID, 'security_alerts', 'acknowledged_idx', 'key', ['acknowledged']);
        await databases.createIndex(DATABASE_ID, 'security_alerts', 'timestamp_idx', 'key', ['timestamp']);
        console.log('✅ security_alerts indexes created\n');

        console.log('🎉 All security collections set up successfully!\n');
        console.log('✅ login_history');
        console.log('✅ trusted_devices');
        console.log('✅ security_alerts');

    } catch (error) {
        console.error('❌ Error setting up collections:', error.message);
        if (error.code === 409) {
            console.log('\n⚠️  Collection may already exist. Check Appwrite Console.');
        }
    }
}

// Run the setup
setupSecurityCollections()
    .then(() => {
        console.log('\n✨ Setup complete!');
        process.exit(0);
    })
    .catch((error) => {
        console.error('\n❌ Setup failed:', error);
        process.exit(1);
    });
