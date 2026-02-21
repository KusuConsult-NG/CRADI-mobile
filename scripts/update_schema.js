const { Client, Databases } = require('node-appwrite');

// Configuration
const ENDPOINT = 'https://fra.cloud.appwrite.io/v1';
const API_KEY = process.env.APPWRITE_API_KEY || '';

if (!API_KEY) {
    console.error('❌ Error: APPWRITE_API_KEY environment variable is required');
    console.log('\nUsage:');
    console.log('  APPWRITE_API_KEY=your_key node scripts/update_schema.js');
    process.exit(1);
}

const PROJECT_ID = '6941cdb400050e7249d5';
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
        console.log(`✅ Found collection: ${collection.name} `);

        const existingAttributes = collection.attributes.map(attr => attr.key);
        console.log(`   Existing attributes: ${existingAttributes.join(', ')} \n`);

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

            console.log(`➕ Adding attribute '${attr.key}'(${attr.type})...`);

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
                    console.log(`   ⚠️  Attribute '${attr.key}' already exists(race condition)`);
                } else {
                    throw error;
                }
            }
        }

        console.log('\n✨ Schema migration completed successfully!');
        console.log('\n📊 Final Schema:');

        const updatedCollection = await databases.getCollection(DATABASE_ID, USERS_COLLECTION_ID);
        updatedCollection.attributes.forEach(attr => {
            console.log(`   - ${attr.key} (${attr.type})${attr.required ? ' [required]' : ''} `);
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
