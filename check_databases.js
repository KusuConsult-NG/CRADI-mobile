const sdk = require('node-appwrite');

// Configuration
const ENDPOINT = 'https://fra.cloud.appwrite.io/v1';
const PROJECT_ID = '6941cdb400050e7249d5';
const API_KEY = process.env.APPWRITE_API_KEY || '';

if (!API_KEY) {
    console.error('❌ Error: Please set your Appwrite API key');
    process.exit(1);
}

// Initialize Appwrite client
const client = new sdk.Client()
    .setEndpoint(ENDPOINT)
    .setProject(PROJECT_ID)
    .setKey(API_KEY);

const databases = new sdk.Databases(client);

async function listDatabases() {
    try {
        console.log('🔍 Checking existing databases in project...\n');

        const response = await databases.list();

        if (response.total === 0) {
            console.log('❌ No databases found in this project.');
            console.log('   This is strange - you should be able to create one.');
            return;
        }

        console.log(`📊 Found ${response.total} database(s):\n`);

        response.databases.forEach((db, index) => {
            console.log(`${index + 1}. Name: ${db.name}`);
            console.log(`   ID: ${db.$id}`);
            console.log(`   Created: ${db.$createdAt}`);
            console.log('');
        });

        // Check if cradi_database exists
        const cradiDb = response.databases.find(db => db.$id === 'cradi_database');

        if (cradiDb) {
            console.log('✅ cradi_database exists!');
            console.log('   You can proceed with creating collections.');
        } else {
            console.log('⚠️  cradi_database does NOT exist.');
            console.log('\n📋 Options:');
            console.log('   1. Delete an unused database to make room');
            console.log('   2. Use an existing database (update DATABASE_ID in scripts)');
            console.log('   3. Upgrade your Appwrite plan for more databases');

            if (response.databases.length > 0) {
                console.log('\n💡 Suggestion:');
                console.log(`   Use existing database: ${response.databases[0].$id}`);
                console.log(`   Update DATABASE_ID in setup_appwrite.js to: '${response.databases[0].$id}'`);
            }
        }

    } catch (error) {
        console.error('\n❌ Error checking databases:', error.message);
        if (error.response) {
            console.error('   Response:', error.response);
        }
    }
}

listDatabases();
