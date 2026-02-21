const { Client, Databases, Users, Storage } = require('node-appwrite');

// Configuration
const ENDPOINT = 'https://fra.cloud.appwrite.io/v1';
const API_KEY = process.env.APPWRITE_API_KEY || '';
const PROJECT_ID = '6941cdb400050e7249d5';
const DATABASE_ID = '6941e2c2003705bb5a25';
const BUCKET_ID = '6941e4e10034186aded8';

if (!API_KEY) {
    console.error('❌ Error: APPWRITE_API_KEY environment variable is required');
    console.log('\nUsage:');
    console.log('  APPWRITE_API_KEY=your_key node scripts/clear_db.js');
    process.exit(1);
}

// Initialize Appwrite client
const client = new Client()
    .setEndpoint(ENDPOINT)
    .setProject(PROJECT_ID)
    .setKey(API_KEY);

const databases = new Databases(client);
const users = new Users(client);
const storage = new Storage(client);

const COLLECTIONS = [
    'users', 'reports', 'chats', 'messages', 'emergency_contacts',
    'trusted_devices', 'login_history', 'knowledge_base', 'alerts', 'verifications'
];

async function clearDB() {
    console.log('🚀 Starting Appwrite DB and Auth cleanup...\n');

    try {
        // 1. Delete all Auth Users
        console.log('🧹 Clearing Auth Users...');
        let hasMoreUsers = true;
        let authCount = 0;
        while (hasMoreUsers) {
            const userList = await users.list();
            if (userList.users.length === 0) {
                hasMoreUsers = false;
                break;
            }
            for (const user of userList.users) {
                await users.delete(user.$id);
                authCount++;
                console.log(`    Deleted user ${user.$id} (${user.email || 'no-email'})`);
            }
        }
        console.log(`✅ Deleted ${authCount} Auth Users.\n`);

        // 2. Delete all Documents in all Collections
        console.log('🧹 Clearing Database Collections...');
        for (const collectionId of COLLECTIONS) {
            console.log(`  -> Clearing collection: ${collectionId}`);
            let hasMoreDocs = true;
            let docCount = 0;
            try {
                while (hasMoreDocs) {
                    const docList = await databases.listDocuments(DATABASE_ID, collectionId);
                    if (docList.documents.length === 0) {
                        hasMoreDocs = false;
                        break;
                    }
                    for (const doc of docList.documents) {
                        await databases.deleteDocument(DATABASE_ID, collectionId, doc.$id);
                        docCount++;
                    }
                }
                console.log(`    ✅ Deleted ${docCount} documents from ${collectionId}.`);
            } catch (err) {
                if (err.code === 404) {
                    console.log(`    ⚠️ Collection ${collectionId} not found. Skipping.`);
                } else {
                    console.error(`    ❌ Error clearing ${collectionId}:`, err.message);
                }
            }
        }

        // 3. Clear Storage Bucket
        console.log('\n🧹 Clearing Storage Bucket...');
        let hasMoreFiles = true;
        let fileCount = 0;
        try {
            while (hasMoreFiles) {
                const fileList = await storage.listFiles(BUCKET_ID);
                if (fileList.files.length === 0) {
                    hasMoreFiles = false;
                    break;
                }
                for (const file of fileList.files) {
                    await storage.deleteFile(BUCKET_ID, file.$id);
                    fileCount++;
                    console.log(`    Deleted file ${file.name}`);
                }
            }
            console.log(`✅ Deleted ${fileCount} files from bucket.\n`);
        } catch (err) {
            console.error(`    ❌ Error clearing storage bucket:`, err.message);
        }

        console.log('🎉 Cleanup complete!\n');

    } catch (error) {
        console.error('❌ Critical Error during cleanup:', error);
    }
}

clearDB();
