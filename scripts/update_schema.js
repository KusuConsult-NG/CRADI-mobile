const { Client, Databases } = require('node-appwrite');

// Configuration
const ENDPOINT = 'https://fra.cloud.appwrite.io/v1';
const PROJECT_ID = '6941cdb400050e7249d5';
const API_KEY = 'standard_363605f23a8f9643259352ca7f67a50813d5e7691a01d3648d86b39bc83162502ac8abe13aead2ead4c10a3f4abac303cc5dd7e69774862fb46a24811c0c8c96297ef862eedf43573b919c3d84a3c20539d63a6ea88db39cf56ebcfa16c1e35c492dc289adba74074ad878d6761272d43f9fcf0062b0393466942ba26be005f2';
const DATABASE_ID = '6941e2c2003705bb5a25';
const USERS_COLLECTION_ID = 'users';

// Initialize Appwrite client
const client = new Client()
    .setEndpoint(ENDPOINT)
    .setProject(PROJECT_ID)
    .setKey(API_KEY);

const databases = new Databases(client);

async function updateSchema() {
    console.log('🚀 Starting Appwrite Schema Migration...\n');

    try {
        // 1. Get current collection to see existing attributes
        console.log('📋 Fetching current collection schema...');
        const collection = await databases.getCollection(DATABASE_ID, USERS_COLLECTION_ID);
        console.log(`✅ Found collection: ${collection.name}`);

        const existingAttributes = collection.attributes.map(attr => attr.key);
        console.log(`   Existing attributes: ${existingAttributes.join(', ')}\n`);

        // 2. Define required attributes
        const requiredAttributes = [
            {
                key: 'biometricsEnabled',
                type: 'boolean',
                required: false,
                default: false,
                description: 'Whether biometric authentication is enabled for this user'
            },
            {
                key: 'lastLoginAt',
                type: 'datetime',
                required: false,
                default: null,
                description: 'Timestamp of the user\'s last login'
            },
            {
                key: 'isVerified',
                type: 'boolean',
                required: false,
                default: false,
                description: 'Whether the user has verified their account'
            }
        ];

        // 3. Add missing attributes
        for (const attr of requiredAttributes) {
            if (existingAttributes.includes(attr.key)) {
                console.log(`⏭️  Skipping '${attr.key}' - already exists`);
                continue;
            }

            console.log(`➕ Adding attribute '${attr.key}' (${attr.type})...`);

            try {
                if (attr.type === 'boolean') {
                    await databases.createBooleanAttribute(
                        DATABASE_ID,
                        USERS_COLLECTION_ID,
                        attr.key,
                        attr.required,
                        attr.default
                    );
                } else if (attr.type === 'datetime') {
                    await databases.createDatetimeAttribute(
                        DATABASE_ID,
                        USERS_COLLECTION_ID,
                        attr.key,
                        attr.required,
                        attr.default
                    );
                }

                console.log(`   ✅ Successfully added '${attr.key}'`);

                // Wait a bit for Appwrite to process
                await new Promise(resolve => setTimeout(resolve, 2000));

            } catch (error) {
                if (error.code === 409) {
                    console.log(`   ⚠️  Attribute '${attr.key}' already exists (race condition)`);
                } else {
                    throw error;
                }
            }
        }

        console.log('\n✨ Schema migration completed successfully!');
        console.log('\n📊 Final Schema:');

        const updatedCollection = await databases.getCollection(DATABASE_ID, USERS_COLLECTION_ID);
        updatedCollection.attributes.forEach(attr => {
            console.log(`   - ${attr.key} (${attr.type})${attr.required ? ' [required]' : ''}`);
        });

    } catch (error) {
        console.error('\n❌ Error updating schema:', error.message);
        if (error.response) {
            console.error('   Response:', error.response);
        }
        process.exit(1);
    }
}

// Run the migration
updateSchema();
