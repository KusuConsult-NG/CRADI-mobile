const sdk = require('node-appwrite');

// Configuration
const ENDPOINT = 'https://cloud.appwrite.io/v1';
const PROJECT_ID = '6941cdb400050e7249d5';
const BUCKET_ID = '6941e4e10034186aded8'; // Shared bucket for all images

// Get API key from environment
const API_KEY = process.env.APPWRITE_API_KEY;

if (!API_KEY || API_KEY === 'YOUR_API_KEY_HERE') {
    console.error('❌ Error: Please set your Appwrite API key');
    console.error('   Run: APPWRITE_API_KEY=your_key node fix_storage_permissions.js');
    process.exit(1);
}

// Initialize Appwrite client
const client = new sdk.Client()
    .setEndpoint(ENDPOINT)
    .setProject(PROJECT_ID)
    .setKey(API_KEY);

const storage = new sdk.Storage(client);

async function fixStoragePermissions() {
    try {
        console.log('🚀 Fixing Storage Bucket Permissions\n');
        console.log(`📡 Endpoint: ${ENDPOINT}`);
        console.log(`🆔 Project: ${PROJECT_ID}`);
        console.log(`🪣 Bucket: ${BUCKET_ID}\n`);

        // Update bucket permissions to allow authenticated users to upload
        console.log('🔧 Updating bucket permissions...');

        await storage.updateBucket(
            BUCKET_ID,
            'Shared Images Bucket', // name
            [
                'read("any")',           // Anyone can read/view images
                'create("users")',       // Authenticated users can upload
                'update("users")',       // Authenticated users can update
                'delete("users")'        // Authenticated users can delete
            ],
            false,  // fileSecurity (use bucket-level permissions)
            true,   // enabled
            undefined, // maximumFileSize (keep existing)
            undefined, // allowedFileExtensions (keep existing)
            undefined, // compression
            undefined, // encryption
            undefined  // antivirus
        );

        console.log('   ✅ Bucket permissions updated successfully\n');
        console.log('📋 New Permissions:');
        console.log('   Read: anyone (for viewing images)');
        console.log('   Create: authenticated users');
        console.log('   Update: authenticated users');
        console.log('   Delete: authenticated users\n');

        console.log('🎉 Storage permissions fixed!');
        console.log('\n💡 Next: Test profile image upload in the app');

        process.exit(0);
    } catch (error) {
        console.error('\n❌ Failed to fix storage permissions:', error.message);
        if (error.response) {
            console.error('   Response:', error.response);
        }
        process.exit(1);
    }
}

fixStoragePermissions();
