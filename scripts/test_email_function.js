const sdk = require('node-appwrite');

const CONFIG = {
    endpoint: process.env.APPWRITE_ENDPOINT || 'https://fra.cloud.appwrite.io/v1',
    projectId: process.env.APPWRITE_PROJECT_ID || '6941cdb400050e7249d5',
    apiKey: process.env.APPWRITE_API_KEY, // User API Key or JWT (we'll use API Key for test)
};

async function testEmail() {
    if (!CONFIG.apiKey) {
        console.error('❌ Error: APPWRITE_API_KEY is required');
        process.exit(1);
    }

    const client = new sdk.Client()
        .setEndpoint(CONFIG.endpoint)
        .setProject(CONFIG.projectId)
        .setKey(CONFIG.apiKey);

    const functions = new sdk.Functions(client);
    const FUNCTION_ID = 'alert-distribution';

    console.log('🧪 Testing Email Function...');

    try {
        const func = await functions.get(FUNCTION_ID);
        console.log(`ℹ️ Function Info:`);
        console.log(`   Name: ${func.name}`);
        console.log(`   Runtime: ${func.runtime}`);
        console.log(`   Entry Point (as configured): ${func.entrypoint}`); // Note: casing might vary
        console.log(`   Execute Access: ${JSON.stringify(func.execute)}`);
    } catch (e) {
        console.error('⚠️ Could not get function details:', e.message);
    }

    // Check Deployment Status First
    try {
        console.log('🔎 Checking latest deployment status...');
        const deployments = await functions.listDeployments(FUNCTION_ID, [
            sdk.Query.orderDesc('$createdAt'),
            sdk.Query.limit(1)
        ]);

        if (deployments.deployments.length > 0) {
            let latest = deployments.deployments[0];
            console.log(`   Latest Deployment ID: ${latest.$id}`);

            // Poll for build completion
            while (latest.status === 'building' || latest.status === 'processing') {
                console.log(`⏳ Deployment ${latest.$id} is ${latest.status}... waiting 5s...`);
                await new Promise(r => setTimeout(r, 5000));

                // Refresh status
                const refreshed = await functions.getDeployment(FUNCTION_ID, latest.$id);
                latest = refreshed;
            }

            console.log(`   Final Build Status: ${latest.status}`);
            console.log(`   Build Time: ${latest.buildTime}s`);

            if (latest.status === 'failed') {
                console.error('❌ LATEST DEPLOYMENT FAILED TO BUILD!');
                console.error('   Build Logs:', latest.buildStdout + '\n' + latest.buildStderr);
                return; // Stop testing
            }
        }
    } catch (e) {
        console.error('⚠️ Could not check deployments:', e.message);
    }

    try {
        const payload = JSON.stringify({
            type: 'direct-email',
            template: 'verification',
            to: 'ewercradi@gmail.com', // Updated for Resend Test Mode
            data: {
                name: 'Test User',
                code: 'TEST-123456',
                role: 'EWM'
            }
        });

        const execution = await functions.createExecution(
            FUNCTION_ID,
            payload
        );

        console.log(`✅ Execution Created: ${execution.$id}`);

        let status = execution.status;
        let result = execution;

        console.log('⏳ Waiting for execution to complete...');
        for (let i = 0; i < 10; i++) {
            if (status !== 'processing' && status !== 'waiting') break;
            await new Promise(r => setTimeout(r, 1000));
            result = await functions.getExecution(FUNCTION_ID, execution.$id);
            status = result.status;
        }

        console.log(`   Final Status: ${status}`);
        console.log(`   Response Body: ${result.responseBody}`);
        console.log(`   Errors: ${result.responseStderr}`);
        console.log(`   Logs: ${result.logs}`);

        if (status === 'failed') {
            console.error('❌ Function Execution Failed!');
        }

    } catch (e) {
        console.error(`❌ Test Failed: ${e.message}`);
        if (e.response) {
            console.error('   Details:', e.response);
        }
    }
}

testEmail();
