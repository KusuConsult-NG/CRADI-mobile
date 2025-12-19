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

async function addUsersAttributes() {
    console.log('👥 Adding attributes to users collection...');

    try {
        await databases.createStringAttribute(DATABASE_ID, 'users', 'email', 255, true);
        console.log('   ✅ email');
    } catch (e) { console.log(`   ℹ️  email: ${e.message}`); }

    try {
        await databases.createStringAttribute(DATABASE_ID, 'users', 'name', 255, true);
        console.log('   ✅ name');
    } catch (e) { console.log(`   ℹ️  name: ${e.message}`); }

    try {
        await databases.createStringAttribute(DATABASE_ID, 'users', 'role', 50, true, 'ewm');
        console.log('   ✅ role');
    } catch (e) { console.log(`   ℹ️  role: ${e.message}`); }

    try {
        await databases.createStringAttribute(DATABASE_ID, 'users', 'phoneNumber', 20, false);
        console.log('   ✅ phoneNumber');
    } catch (e) { console.log(`   ℹ️  phoneNumber: ${e.message}`); }

    try {
        await databases.createStringAttribute(DATABASE_ID, 'users', 'profileImageId', 255, false);
        console.log('   ✅ profileImageId');
    } catch (e) { console.log(`   ℹ️  profileImageId: ${e.message}`); }

    try {
        await databases.createStringAttribute(DATABASE_ID, 'users', 'registrationCode', 20, false);
        console.log('   ✅ registrationCode');
    } catch (e) { console.log(`   ℹ️  registrationCode: ${e.message}`); }

    try {
        await databases.createBooleanAttribute(DATABASE_ID, 'users', 'biometricsEnabled', false, false);
        console.log('   ✅ biometricsEnabled');
    } catch (e) { console.log(`   ℹ️  biometricsEnabled: ${e.message}`); }

    try {
        await databases.createDatetimeAttribute(DATABASE_ID, 'users', 'createdAt', true);
        console.log('   ✅ createdAt');
    } catch (e) { console.log(`   ℹ️  createdAt: ${e.message}`); }

    try {
        await databases.createDatetimeAttribute(DATABASE_ID, 'users', 'lastLoginAt', false);
        console.log('   ✅ lastLoginAt');
    } catch (e) { console.log(`   ℹ️  lastLoginAt: ${e.message}`); }

    console.log('\\n   Waiting for attributes to be available...');
    await new Promise(resolve => setTimeout(resolve, 3000));

    console.log('\\n👥 Adding indexes to users collection...');
    try {
        await databases.createIndex(DATABASE_ID, 'users', 'email_idx', 'unique', ['email']);
        console.log('   ✅ email_idx (unique)');
    } catch (e) { console.log(`   ℹ️  email_idx: ${e.message}`); }

    try {
        await databases.createIndex(DATABASE_ID, 'users', 'registrationCode_idx', 'unique', ['registrationCode']);
        console.log('   ✅ registrationCode_idx (unique)');
    } catch (e) { console.log(`   ℹ️  registrationCode_idx: ${e.message}`); }

    try {
        await databases.createIndex(DATABASE_ID, 'users', 'role_idx', 'key', ['role']);
        console.log('   ✅ role_idx');
    } catch (e) { console.log(`   ℹ️  role_idx: ${e.message}`); }
}

async function addReportsAttributes() {
    console.log('\\n📋 Adding attributes to reports collection...');

    try { await databases.createStringAttribute(DATABASE_ID, 'reports', 'userId', 255, true); console.log('   ✅ userId'); } catch (e) { console.log(`   ℹ️  userId: ${e.message}`); }
    try { await databases.createStringAttribute(DATABASE_ID, 'reports', 'hazardType', 100, true); console.log('   ✅ hazardType'); } catch (e) { console.log(`   ℹ️  hazardType: ${e.message}`); }
    try { await databases.createStringAttribute(DATABASE_ID, 'reports', 'severity', 50, true); console.log('   ✅ severity'); } catch (e) { console.log(`   ℹ️  severity: ${e.message}`); }
    try { await databases.createFloatAttribute(DATABASE_ID, 'reports', 'latitude', true); console.log('   ✅ latitude'); } catch (e) { console.log(`   ℹ️  latitude: ${e.message}`); }
    try { await databases.createFloatAttribute(DATABASE_ID, 'reports', 'longitude', true); console.log('   ✅ longitude'); } catch (e) { console.log(`   ℹ️  longitude: ${e.message}`); }
    try { await databases.createStringAttribute(DATABASE_ID, 'reports', 'locationDetails', 500, true); console.log('   ✅ locationDetails'); } catch (e) { console.log(`   ℹ️  locationDetails: ${e.message}`); }
    try { await databases.createStringAttribute(DATABASE_ID, 'reports', 'description', 2000, false); console.log('   ✅ description'); } catch (e) { console.log(`   ℹ️  description: ${e.message}`); }
    try { await databases.createStringAttribute(DATABASE_ID, 'reports', 'imageIds', 255, false, undefined, true); console.log('   ✅ imageIds'); } catch (e) { console.log(`   ℹ️  imageIds: ${e.message}`); }
    try { await databases.createStringAttribute(DATABASE_ID, 'reports', 'status', 50, true, 'pending'); console.log('   ✅ status'); } catch (e) { console.log(`   ℹ️  status: ${e.message}`); }
    try { await databases.createBooleanAttribute(DATABASE_ID, 'reports', 'isAlert', false, false); console.log('   ✅ isAlert'); } catch (e) { console.log(`   ℹ️  isAlert: ${e.message}`); }
    try { await databases.createDatetimeAttribute(DATABASE_ID, 'reports', 'submittedAt', true); console.log('   ✅ submittedAt'); } catch (e) { console.log(`   ℹ️  submittedAt: ${e.message}`); }
    try { await databases.createIntegerAttribute(DATABASE_ID, 'reports', 'verificationCount', false, 0); console.log('   ✅ verificationCount'); } catch (e) { console.log(`   ℹ️  verificationCount: ${e.message}`); }

    console.log('\\n   Waiting for attributes to be available...');
    await new Promise(resolve => setTimeout(resolve, 3000));

    console.log('\\n📋 Adding indexes to reports collection...');
    try { await databases.createIndex(DATABASE_ID, 'reports', 'userId_idx', 'key', ['userId']); console.log('   ✅ userId_idx'); } catch (e) { console.log(`   ℹ️  userId_idx: ${e.message}`); }
    try { await databases.createIndex(DATABASE_ID, 'reports', 'status_idx', 'key', ['status']); console.log('   ✅ status_idx'); } catch (e) { console.log(`   ℹ️  status_idx: ${e.message}`); }
    try { await databases.createIndex(DATABASE_ID, 'reports', 'isAlert_idx', 'key', ['isAlert']); console.log('   ✅ isAlert_idx'); } catch (e) { console.log(`   ℹ️  isAlert_idx: ${e.message}`); }
    try { await databases.createIndex(DATABASE_ID, 'reports', 'submittedAt_idx', 'key', ['submittedAt'], ['DESC']); console.log('   ✅ submittedAt_idx'); } catch (e) { console.log(`   ℹ️  submittedAt_idx: ${e.message}`); }
}

async function addMessagesAttributes() {
    console.log('\\n💬 Adding attributes to messages collection...');

    try { await databases.createStringAttribute(DATABASE_ID, 'messages', 'chatId', 255, true); console.log('   ✅ chatId'); } catch (e) { console.log(`   ℹ️  chatId: ${e.message}`); }
    try { await databases.createStringAttribute(DATABASE_ID, 'messages', 'senderId', 255, true); console.log('   ✅ senderId'); } catch (e) { console.log(`   ℹ️  senderId: ${e.message}`); }
    try { await databases.createStringAttribute(DATABASE_ID, 'messages', 'senderName', 255, true); console.log('   ✅ senderName'); } catch (e) { console.log(`   ℹ️  senderName: ${e.message}`); }
    try { await databases.createStringAttribute(DATABASE_ID, 'messages', 'message', 5000, true); console.log('   ✅ message'); } catch (e) { console.log(`   ℹ️  message: ${e.message}`); }
    try { await databases.createStringAttribute(DATABASE_ID, 'messages', 'type', 50, true, 'text'); console.log('   ✅ type'); } catch (e) { console.log(`   ℹ️  type: ${e.message}`); }
    try { await databases.createDatetimeAttribute(DATABASE_ID, 'messages', 'sentAt', true); console.log('   ✅ sentAt'); } catch (e) { console.log(`   ℹ️  sentAt: ${e.message}`); }
    try { await databases.createBooleanAttribute(DATABASE_ID, 'messages', 'read', false, false); console.log('   ✅ read'); } catch (e) { console.log(`   ℹ️  read: ${e.message}`); }

    console.log('\\n   Waiting for attributes to be available...');
    await new Promise(resolve => setTimeout(resolve, 3000));

    console.log('\\n💬 Adding indexes to messages collection...');
    try { await databases.createIndex(DATABASE_ID, 'messages', 'chatId_idx', 'key', ['chatId']); console.log('   ✅ chatId_idx'); } catch (e) { console.log(`   ℹ️  chatId_idx: ${e.message}`); }
    try { await databases.createIndex(DATABASE_ID, 'messages', 'sentAt_idx', 'key', ['sentAt'], ['DESC']); console.log('   ✅ sentAt_idx'); } catch (e) { console.log(`   ℹ️  sentAt_idx: ${e.message}`); }
}

async function addEmergencyContactsAttributes() {
    console.log('\\n🚨 Adding attributes to emergency_contacts collection...');

    try { await databases.createStringAttribute(DATABASE_ID, 'emergency_contacts', 'userId', 255, true); console.log('   ✅ userId'); } catch (e) { console.log(`   ℹ️  userId: ${e.message}`); }
    try { await databases.createStringAttribute(DATABASE_ID, 'emergency_contacts', 'name', 255, true); console.log('   ✅ name'); } catch (e) { console.log(`   ℹ️  name: ${e.message}`); }
    try { await databases.createStringAttribute(DATABASE_ID, 'emergency_contacts', 'phone', 20, true); console.log('   ✅ phone'); } catch (e) { console.log(`   ℹ️  phone: ${e.message}`); }
    try { await databases.createStringAttribute(DATABASE_ID, 'emergency_contacts', 'relationship', 100, false); console.log('   ✅ relationship'); } catch (e) { console.log(`   ℹ️  relationship: ${e.message}`); }
    try { await databases.createDatetimeAttribute(DATABASE_ID, 'emergency_contacts', 'createdAt', true); console.log('   ✅ createdAt'); } catch (e) { console.log(`   ℹ️  createdAt: ${e.message}`); }

    console.log('\\n   Waiting for attributes to be available...');
    await new Promise(resolve => setTimeout(resolve, 3000));

    console.log('\\n🚨 Adding indexes to emergency_contacts collection...');
    try { await databases.createIndex(DATABASE_ID, 'emergency_contacts', 'userId_idx', 'key', ['userId']); console.log('   ✅ userId_idx'); } catch (e) { console.log(`   ℹ️  userId_idx: ${e.message}`); }
}

async function main() {
    console.log('🔧 Adding attributes and indexes to collections...\\n');

    await addUsersAttributes();
    await addReportsAttributes();
    await addMessagesAttributes();
    await addEmergencyContactsAttributes();

    console.log('\\n🎉 Done! Run verification script to confirm.');
}

main().catch(console.error);
