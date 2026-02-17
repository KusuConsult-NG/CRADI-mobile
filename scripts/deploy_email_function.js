const sdk = require('node-appwrite');
const { InputFile } = require('node-appwrite/file');
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

// Configuration
const CONFIG = {
    endpoint: process.env.APPWRITE_ENDPOINT || 'https://fra.cloud.appwrite.io/v1',
    projectId: process.env.APPWRITE_PROJECT_ID || '6941cdb400050e7249d5',
    apiKey: process.env.APPWRITE_API_KEY,
    resendApiKey: process.env.RESEND_API_KEY,
};

async function deployEmailFunction() {
    if (!CONFIG.apiKey) {
        console.error('❌ Error: APPWRITE_API_KEY environment variable is required');
        process.exit(1);
    }

    console.log('🚀 Deploying Send Email Function (Resend Only)...');
    console.log(`Project ID: ${CONFIG.projectId}`);

    const client = new sdk.Client()
        .setEndpoint(CONFIG.endpoint)
        .setProject(CONFIG.projectId)
        .setKey(CONFIG.apiKey);

    const functions = new sdk.Functions(client);

    const FUNCTION_ID = 'alert-distribution';
    const FUNCTION_NAME = 'Alert Distribution';
    const RUNTIME = 'node-20.0';

    // 1. Check if function exists
    try {
        console.log(`\n🔍 Checking if function '${FUNCTION_ID}' exists...`);
        await functions.get(FUNCTION_ID);
        console.log('  ✅ Function exists.');
    } catch (e) {
        if (e.code === 404) {
            console.log('  ⚠️ Function not found. Creating...');
            try {
                await functions.create(
                    FUNCTION_ID,
                    FUNCTION_NAME,
                    RUNTIME
                );
                console.log('  ✅ Function created.');
            } catch (createError) {
                console.error(`  ❌ Failed to create function: ${createError.message}`);
                process.exit(1);
            }
        } else {
            console.error(`  ❌ Error checking function: ${e.message}`);
            process.exit(1);
        }
    }

    // 2. Update Environment Variables
    console.log('\n⚙️ Configuring environment variables...');

    // SMTP Vars removed to enforce Resend usage
    const variables = {
        'RESEND_API_KEY': CONFIG.resendApiKey || '',
        'FROM_EMAIL': process.env.FROM_EMAIL || 'no-reply@ewer.cradil.org',
        'FROM_NAME': process.env.FROM_NAME || 'EWER App',
        'APPWRITE_FUNCTION_ENDPOINT': CONFIG.endpoint,
        'APPWRITE_FUNCTION_PROJECT_ID': CONFIG.projectId
    };

    // Build current variable map to decide create vs update
    let currentVars = {};
    try {
        const varList = await functions.listVariables(FUNCTION_ID);
        varList.variables.forEach(v => {
            currentVars[v.key] = v;
        });
    } catch (e) {
        console.warn('  ⚠️ Could not list existing variables, assuming blank slate or fallback to check-one-by-one');
    }

    for (const [key, value] of Object.entries(variables)) {
        if (!value) continue; // Skip empty

        try {
            if (currentVars[key]) {
                // Update
                if (currentVars[key].value !== value) {
                    await functions.updateVariable(FUNCTION_ID, currentVars[key].$id, key, value);
                    console.log(`  ✅ Updated ${key}`);
                } else {
                    console.log(`  KV ${key} is up to date.`);
                }
            } else {
                // Create
                await functions.createVariable(FUNCTION_ID, key, value);
                console.log(`  ✅ Created ${key}`);
            }
        } catch (e) {
            try {
                await functions.createVariable(FUNCTION_ID, key, value);
                console.log(`  ✅ Created ${key} (fallback)`);
            } catch (createErr) {
                console.error(`  ⚠️ Failed to set ${key}: ${e.message}`);
            }
        }
    }

    // Always ensure Entrypoint is index.js
    try {
        console.log('\n⚙️ updating function configuration...');
        await functions.update(
            FUNCTION_ID,
            FUNCTION_NAME,
            RUNTIME,
            ['users'], // execute 
            undefined, // events
            undefined, // schedule
            undefined, // timeout
            undefined, // enabled
            undefined, // logging
            'index.js' // entrypoint
        );
        console.log(`  ✅ Enforced entrypoint: index.js | runtime: ${RUNTIME} | execute: users`);
    } catch (e) {
        console.error(`  ⚠️ Failed to update entrypoint: ${e.message}`);
    }

    // 3. Create Deployment
    console.log('\n📦 Creating deployment...');
    const functionDir = path.join(__dirname, '../functions/alert-distribution');
    const tarFile = path.join(__dirname, 'alert-distribution.tar.gz');

    try {
        // Create tar.gz of the function directory
        console.log('  Compressing function code (INCLUDING node_modules)...');
        execSync(`cd "${functionDir}" && tar -czf "${tarFile}" .`);

        console.log('  Uploading Code...');
        if (!fs.existsSync(tarFile)) {
            throw new Error('Tar file was not created');
        }

        const inputFile = InputFile.fromPath(tarFile, 'alert-distribution.tar.gz');

        const deployment = await functions.createDeployment(
            FUNCTION_ID,
            inputFile,
            true // Activate immediately
        );

        console.log(`  ✅ Deployment created! ID: ${deployment.$id}`);
        console.log(`  ✅ Status: ${deployment.status}`);
        console.log(`  ✅ Build ID: ${deployment.buildId}`);

        // Clean up
        fs.unlinkSync(tarFile);

    } catch (e) {
        console.error(`  ❌ Deployment failed: ${e.message}`);
        if (fs.existsSync(tarFile)) fs.unlinkSync(tarFile);
        process.exit(1);
    }

    console.log('\n✨ deployment process initiated. Check Appwrite Console for build status.');
}

deployEmailFunction().catch(console.error);
