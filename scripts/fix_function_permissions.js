const sdk = require('node-appwrite');

// Configuration
const CONFIG = {
    endpoint: process.env.APPWRITE_ENDPOINT || 'https://fra.cloud.appwrite.io/v1',
    projectId: process.env.APPWRITE_PROJECT_ID || '6941cdb400050e7249d5',
    apiKey: process.env.APPWRITE_API_KEY,
};

async function fixPermissions() {
    if (!CONFIG.apiKey) {
        console.error('❌ Error: APPWRITE_API_KEY is required');
        process.exit(1);
    }

    const client = new sdk.Client()
        .setEndpoint(CONFIG.endpoint)
        .setProject(CONFIG.projectId)
        .setKey(CONFIG.apiKey);

    const functions = new sdk.Functions(client);
    const FUNCTION_ID = 'alert-distribution'; // The one we are using

    try {
        console.log(`Updating permissions for ${FUNCTION_ID}...`);

        // Grant execute access to registered users
        await functions.update(
            FUNCTION_ID,
            'Alert Distribution', // Name
            undefined, // runtime - undefined to keep current
            ['users'], // Execute permissions - allow logged in users
            [], // Events
            undefined, // Schedule
            15, // Timeout
            true // Enabled
        );

        console.log('✅ Permissions updated: role:users can now execute this function.');

    } catch (e) {
        console.error(`❌ Failed to update permissions: ${e.message}`);
    }
}

fixPermissions();
