const sdk = require('node-appwrite');

// Configuration
const ENDPOINT = 'https://cloud.appwrite.io/v1';
const PROJECT_ID = '6941cdb400050e7249d5';
const DATABASE_ID = '6941e2c2003705bb5a25';

// Get API key from environment
const API_KEY = process.env.APPWRITE_API_KEY || 'YOUR_API_KEY_HERE';

if (API_KEY === 'YOUR_API_KEY_HERE') {
    console.error('❌ Error: Please set your Appwrite API key');
    console.error('   Get it from: https://cloud.appwrite.io/console/project-6941cdb400050e7249d5/auth/apikeys');
    console.error('   Then run: APPWRITE_API_KEY=your_key node fix_permissions.js');
    process.exit(1);
}

// Initialize Appwrite client
const client = new sdk.Client()
    .setEndpoint(ENDPOINT)
    .setProject(PROJECT_ID)
    .setKey(API_KEY);

const databases = new sdk.Databases(client);

async function updateCollectionPermissions(collectionId, collectionName, permissions) {
    try {
        console.log(`\n🔧 Updating permissions for ${collectionName}...`);

        // Combine read and write permissions into a single array
        const allPermissions = [...permissions.read, ...permissions.write];

        // Update collection permissions
        await databases.updateCollection(
            DATABASE_ID,
            collectionId,
            collectionName,
            allPermissions,
            true,  // documentSecurity - allow document-level permissions
            true   // enabled - keep collection enabled
        );

        console.log(`   ✅ ${collectionName} permissions updated`);
        console.log(`      Read: ${permissions.read.join(', ')}`);
        console.log(`      Write: ${permissions.write.join(', ')}`);

        return true;
    } catch (error) {
        if (error.code === 404) {
            console.log(`   ⚠️  ${collectionName} collection not found - skipping`);
            return false;
        }
        console.error(`   ❌ Error updating ${collectionName}:`, error.message);
        throw error;
    }
}

async function fixAllPermissions() {
    try {
        console.log('🚀 Starting Permission Fix for CRADI Mobile\n');
        console.log(`📡 Endpoint: ${ENDPOINT}`);
        console.log(`🆔 Project: ${PROJECT_ID}`);
        console.log(`📦 Database: ${DATABASE_ID}\n`);

        // Collection permissions configuration
        const collections = [
            {
                id: 'users',
                name: 'Users',
                permissions: {
                    // Anyone can read user documents (for public profiles)
                    // Any authenticated user can create their document
                    // Users can update/delete only their own documents
                    read: ['read("any")'],
                    write: ['create("users")', 'update("users")', 'delete("users")']
                }
            },
            {
                id: 'reports',
                name: 'Reports',
                permissions: {
                    // Anyone can read reports (for viewing hazards on map)
                    // Any authenticated user can create reports
                    // Users can update/delete only their own reports
                    read: ['read("any")'],
                    write: ['create("users")', 'update("users")', 'delete("users")']
                }
            },
            {
                id: 'messages',
                name: 'Messages',
                permissions: {
                    // Any authenticated user can read messages
                    // Any authenticated user can create/update messages
                    read: ['read("users")'],
                    write: ['create("users")', 'update("users")', 'delete("users")']
                }
            },
            {
                id: 'emergency_contacts',
                name: 'Emergency Contacts',
                permissions: {
                    // Only authenticated users can read
                    // Any authenticated user can create/update/delete
                    read: ['read("users")'],
                    write: ['create("users")', 'update("users")', 'delete("users")']
                }
            },
            {
                id: 'login_history',
                name: 'Login History',
                permissions: {
                    // Any authenticated user can read
                    // Any authenticated user can create
                    read: ['read("users")'],
                    write: ['create("users")', 'update("users")']
                }
            },
            {
                id: 'trusted_devices',
                name: 'Trusted Devices',
                permissions: {
                    // Any authenticated user can read
                    // Any authenticated user can create/update/delete
                    read: ['read("users")'],
                    write: ['create("users")', 'update("users")', 'delete("users")']
                }
            },
            {
                id: 'security_alerts',
                name: 'Security Alerts',
                permissions: {
                    // Any authenticated user can read
                    // Any authenticated user can create/update/delete
                    read: ['read("users")'],
                    write: ['create("users")', 'update("users")', 'delete("users")']
                }
            }
        ];

        let successCount = 0;
        let skipCount = 0;

        // Update permissions for each collection
        for (const collection of collections) {
            const result = await updateCollectionPermissions(
                collection.id,
                collection.name,
                collection.permissions
            );

            if (result) {
                successCount++;
            } else {
                skipCount++;
            }
        }

        console.log('\n🎉 Permission fix complete!\n');
        console.log('📋 Summary:');
        console.log(`   ✅ Collections updated: ${successCount}`);
        console.log(`   ⚠️  Collections skipped: ${skipCount}`);
        console.log('\n💡 Next steps:');
        console.log('   1. Test user registration in the app');
        console.log('   2. Verify reports can be created');
        console.log('   3. Test all features requiring database access');
        console.log('\n⚠️  Important Notes:');
        console.log('   - Collection-level permissions control WHO can create/read documents');
        console.log('   - Document-level permissions control access to SPECIFIC documents');
        console.log('   - The "users" role means any authenticated user');
        console.log('   - The "any" role means anyone (including unauthenticated)');

        process.exit(0);
    } catch (error) {
        console.error('\n❌ Permission fix failed:', error.message);
        if (error.response) {
            console.error('   Response:', error.response);
        }
        process.exit(1);
    }
}

// Run the fix
fixAllPermissions();
