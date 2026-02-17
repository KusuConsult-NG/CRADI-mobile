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

    const smtpKeys = ['SMTP_HOST', 'SMTP_PORT', 'SMTP_USER', 'SMTP_PASS', 'SMTP_SECURE'];

    console.log('🔍 Listing variables to find IDs...');

    try {
        const varList = await functions.listVariables(FUNCTION_ID);
        const varsToDelete = varList.variables.filter(v => smtpKeys.includes(v.key));

        if (varsToDelete.length === 0) {
            console.log('  ✅ No SMTP variables found.');
            return;
        }

        console.log(`  found ${varsToDelete.length} variables to delete.`);

        for (const v of varsToDelete) {
            try {
                process.stdout.write(`  Deleting ${v.key} (${v.$id})... `);
                await functions.deleteVariable(FUNCTION_ID, v.$id);
                console.log('✅');
            } catch (e) {
                console.log(`❌ ${e.message}`);
            }
        }
    } catch (e) {
        console.error(`❌ Error listing variables: ${e.message}`);
    }
}

clearSmtpVars();
