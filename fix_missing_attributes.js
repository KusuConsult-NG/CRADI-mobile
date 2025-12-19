const sdk = require('node-appwrite');

const ENDPOINT = 'https://fra.cloud.appwrite.io/v1';
const PROJECT_ID = '6941cdb400050e7249d5';
const DATABASE_ID = '6941e2c2003705bb5a25';
const API_KEY = process.env.APPWRITE_API_KEY || '';

if (!API_KEY) {
    console.error('❌ Please set APPWRITE_API_KEY');
    process.exit(1);
}

const client = new sdk.Client()
    .setEndpoint(ENDPOINT)
    .setProject(PROJECT_ID)
    .setKey(API_KEY);

const databases = new sdk.Databases(client);

async function fixMissingAttributes() {
    console.log('🔧 Adding missing attributes (without defaults for required fields)...\\n');

    // Fix role in users (required without default)
    console.log('👥 Fixing users.role...');
    try {
        await databases.createStringAttribute(DATABASE_ID, 'users', 'role', 50, true);
        console.log('   ✅ role added');
        await new Promise(resolve => setTimeout(resolve, 2000));
        await databases.createIndex(DATABASE_ID, 'users', 'role_idx', 'key', ['role']);
        console.log('   ✅ role_idx added');
    } catch (e) { console.log(`   ℹ️  ${e.message}`); }

    // Fix status in reports (required without default)
    console.log('\\n📋 Fixing reports.status...');
    try {
        await databases.createStringAttribute(DATABASE_ID, 'reports', 'status', 50, true);
        console.log('   ✅ status added');
        await new Promise(resolve => setTimeout(resolve, 2000));
        await databases.createIndex(DATABASE_ID, 'reports', 'status_idx', 'key', ['status']);
        console.log('   ✅ status_idx added');
    } catch (e) { console.log(`   ℹ️  ${e.message}`); }

    // Fix type in messages (required without default)
    console.log('\\n💬 Fixing messages.type...');
    try {
        await databases.createStringAttribute(DATABASE_ID, 'messages', 'type', 50, true);
        console.log('   ✅ type added');
    } catch (e) { console.log(`   ℹ️  ${e.message}`); }

    console.log('\\n🎉 Done!');
}

fixMissingAttributes().catch(console.error);
