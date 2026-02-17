const sdk = require('node-appwrite');

const CONFIG = {
    endpoint: process.env.APPWRITE_ENDPOINT || 'https://fra.cloud.appwrite.io/v1',
    projectId: process.env.APPWRITE_PROJECT_ID || '6941cdb400050e7249d5',
    apiKey: process.env.APPWRITE_API_KEY,
};

async function clearSmtpVars() {
    if (!CONFIG.apiKey) {
        console.error('❌ APPWRITE_API_KEY required');
        process.exit(1);
    }

    const client = new sdk.Client()
        .setEndpoint(CONFIG.endpoint)
        .setProject(CONFIG.projectId)
        .setKey(CONFIG.apiKey);

    const functions = new sdk.Functions(client);
    const FUNCTION_ID = 'alert-distribution';

    const smtpVars = ['SMTP_HOST', 'SMTP_PORT', 'SMTP_USER', 'SMTP_PASS', 'SMTP_SECURE'];

    console.log('🗑️ Clearing SMTP variables...');

    for (const key of smtpVars) {
        try {
            await functions.deleteVariable(FUNCTION_ID, key);
            console.log(`  ✅ Deleted ${key}`);
        } catch (e) {
            console.log(`  ⚠️ Could not delete ${key}: ${e.message}`);
        }
    }

    // Also initiate a new deployment to ensure env vars are picked up? 
    // Usually variables apply to next execution, but sometimes a redeploy is safer.
    // For now just clearing them.
}

clearSmtpVars();
