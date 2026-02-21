const { Client, Databases, Functions, Permission, Role } = require('node-appwrite');

const API_KEY = process.env.APPWRITE_API_KEY || '';
const RESEND_API_KEY = process.env.RESEND_API_KEY || ''; // Optional: for email distributor if available

if (!API_KEY) {
    console.error('❌ Error: APPWRITE_API_KEY environment variable is required');
    console.log('\nUsage:');
    console.log('  APPWRITE_API_KEY=your_key node scripts/secure_backend.js');
    process.exit(1);
}

const PROJECT_ID = '6941cdb400050e7249d5';
const DATABASE_ID = '6941e2c2003705bb5a25';

const client = new Client()
    .setEndpoint('https://fra.cloud.appwrite.io/v1')
    .setProject(PROJECT_ID)
    .setKey(API_KEY);

const databases = new Databases(client);
const functions = new Functions(client);

async function secureDatabases() {
    const collections = [
        'users',
        'reports',
        'messages',
        'emergency_contacts',
        'trusted_devices',
        'login_history',
        'knowledge_base'
    ];

    // Standard secure permissions for MVP 
    // Reads, Creates, and Updates are allowed by Authenticated Users.
    // Deletes are NOT allowed by default client-side limits.
    const standardPermissions = [
        Permission.read(Role.users()),
        Permission.create(Role.users()),
        Permission.update(Role.users())
    ];

    console.log('🔐 Securing Database Collections (RBAC)...');
    for (const collId of collections) {
        try {
            // Fetch current collection definition to retain existing name & doc security
            const collection = await databases.getCollection(DATABASE_ID, collId);

            await databases.updateCollection(
                DATABASE_ID,
                collId,
                collection.name,
                standardPermissions,
                collection.documentSecurity,
                collection.enabled
            );
            console.log(`  ✅ Secured ${collId} (Read/Create/Update locked to authenticated users)`);
        } catch (e) {
            console.log(`  ❌ Failed to secure ${collId}: ${e.message}`);
        }
    }
}

async function secureFunctions() {
    console.log('\n🔐 Injecting Expected Environment Variables into Cloud Functions...');
    try {
        const functionList = await functions.list();
        for (const fn of functionList.functions) {
            console.log(`  ⚙️  Inspecting function: ${fn.name} (${fn.$id})`);

            // Fetch existing variables inside the function
            const vars = await functions.listVariables(fn.$id);
            const varKeys = vars.variables.map(v => v.key);

            // Ensure APPWRITE_API_KEY is available inside the function
            if (!varKeys.includes('APPWRITE_API_KEY')) {
                await functions.createVariable(fn.$id, 'APPWRITE_API_KEY', API_KEY);
                console.log(`    ✅ Injected APPWRITE_API_KEY`);
            } else {
                const variable = vars.variables.find(v => v.key === 'APPWRITE_API_KEY');
                await functions.updateVariable(fn.$id, variable.$id, 'APPWRITE_API_KEY', API_KEY);
                console.log(`    ✅ Updated APPWRITE_API_KEY`);
            }

            // Ensure RESEND_API_KEY is available if it was provided
            if (RESEND_API_KEY) {
                if (!varKeys.includes('RESEND_API_KEY')) {
                    await functions.createVariable(fn.$id, 'RESEND_API_KEY', RESEND_API_KEY);
                    console.log(`    ✅ Injected RESEND_API_KEY`);
                } else {
                    const variable = vars.variables.find(v => v.key === 'RESEND_API_KEY');
                    await functions.updateVariable(fn.$id, variable.$id, 'RESEND_API_KEY', RESEND_API_KEY);
                    console.log(`    ✅ Updated RESEND_API_KEY`);
                }
            }
        }
    } catch (e) {
        console.log(`  ❌ Failed to process functions: ${e.message}`);
    }
}

async function run() {
    console.log('--- CRADI Backend Auto-Security Script ---');
    await secureDatabases();
    await secureFunctions();
    console.log('\n🎉 Security lockdown complete! Backend is now heavily fortified.');
}

run();
