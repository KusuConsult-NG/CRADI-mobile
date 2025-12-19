const sdk = require('node-appwrite');

const ENDPOINT = 'https://fra.cloud.appwrite.io/v1';
const PROJECT_ID = '6941cdb400050e7249d5';
const API_KEY = process.env.APPWRITE_API_KEY || '';

if (!API_KEY) {
    console.error('❌ Error: Please set your Appwrite API key');
    process.exit(1);
}

const client = new sdk.Client()
    .setEndpoint(ENDPOINT)
    .setProject(PROJECT_ID)
    .setKey(API_KEY);

const storage = new sdk.Storage(client);

async function listBuckets() {
    try {
        console.log('🔍 Checking existing storage buckets...\n');

        const response = await storage.listBuckets();

        if (response.total === 0) {
            console.log('❌ No storage buckets found.');
            return;
        }

        console.log(`📊 Found ${response.total} bucket(s):\n`);

        response.buckets.forEach((bucket, index) => {
            console.log(`${index + 1}. Name: ${bucket.name}`);
            console.log(`   ID: ${bucket.$id}`);
            console.log(`   Max file size: ${bucket.maximumFileSize / 1024 / 1024}MB`);
            console.log(`   Extensions: ${bucket.allowedFileExtensions.join(', ')}`);
            console.log('');
        });

        // Check for our buckets
        const profileBucket = response.buckets.find(b => b.$id === 'profile_images');
        const reportBucket = response.buckets.find(b => b.$id === 'report_images');

        console.log('\n✅ Status:');
        console.log(`   profile_images: ${profileBucket ? '✅ EXISTS' : '❌ MISSING'}`);
        console.log(`   report_images: ${reportBucket ? '✅ EXISTS' : '❌ MISSING'}`);

    } catch (error) {
        console.error('\n❌ Error:', error.message);
    }
}

listBuckets();
