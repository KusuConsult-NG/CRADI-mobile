const sdk = require('node-appwrite');

// Configuration
const CONFIG = {
    endpoint: process.env.APPWRITE_ENDPOINT || 'https://fra.cloud.appwrite.io/v1',
    projectId: process.env.APPWRITE_PROJECT_ID || '6941cdb400050e7249d5',
    databaseId: process.env.DATABASE_ID || '6941e2c2003705bb5a25',
    apiKey: process.env.APPWRITE_API_KEY,
};

async function addMissingAttributes() {
    if (!CONFIG.apiKey) {
        console.error('❌ Error: APPWRITE_API_KEY environment variable is required');
        console.log('\nUsage:');
        console.log('  APPWRITE_API_KEY=your_key node scripts/fix_statistics_collection.js');
        process.exit(1);
    }

    console.log('🔧 Fixing Statistics Collection - Adding Missing Attributes\n');

    const client = new sdk.Client()
        .setEndpoint(CONFIG.endpoint)
        .setProject(CONFIG.projectId)
        .setKey(CONFIG.apiKey);

    const databases = new sdk.Databases(client);

    try {
        // Check current collection state
        const collection = await databases.getCollection(CONFIG.databaseId, 'statistics');
        console.log(`Current collection has ${collection.attributes.length} attribute(s)\n`);

        const existingAttrs = collection.attributes.map(a => a.key);
        console.log('Existing attributes:', existingAttrs.join(', '));
        console.log('');

        const requiredAttrs = ['timestamp', 'totalCount', 'validatedCount', 'escalatedCount'];
        const missingAttrs = requiredAttrs.filter(attr => !existingAttrs.includes(attr));

        if (missingAttrs.length === 0) {
            console.log('✅ All required attributes already exist!');
            return;
        }

        console.log(`Found ${missingAttrs.length} missing attribute(s): ${missingAttrs.join(', ')}\n`);

        // Add missing attributes one by one
        for (const attr of missingAttrs) {
            try {
                if (attr === 'timestamp') {
                    await databases.createStringAttribute(
                        CONFIG.databaseId,
                        'statistics',
                        'timestamp',
                        255,
                        true // required
                    );
                    console.log('  ✅ Added: timestamp (string)');
                } else {
                    await databases.createIntegerAttribute(
                        CONFIG.databaseId,
                        'statistics',
                        attr,
                        true // required (no default for required fields)
                    );
                    console.log(`  ✅ Added: ${attr} (integer)`);
                }

                // Wait between attribute creations
                await new Promise(resolve => setTimeout(resolve, 2000));
            } catch (error) {
                if (error.code === 409) {
                    console.log(`  ⚠️  ${attr} already exists (skipping)`);
                } else {
                    console.error(`  ❌ Failed to add ${attr}:`, error.message);
                }
            }
        }

        // Verify final state
        console.log('\n📊 Verification...');
        const updated = await databases.getCollection(CONFIG.databaseId, 'statistics');
        const finalAttrs = updated.attributes.map(a => a.key);

        console.log(`Final attributes (${finalAttrs.length}):`, finalAttrs.join(', '));

        const stillMissing = requiredAttrs.filter(attr => !finalAttrs.includes(attr));
        if (stillMissing.length > 0) {
            console.log(`\n⚠️  Still missing: ${stillMissing.join(', ')}`);
            console.log('You may need to add these manually in Appwrite Console');
        } else {
            console.log('\n✅ Statistics collection is now complete!');
        }

    } catch (error) {
        console.error(`\n❌ Error: ${error.message}`);
        process.exit(1);
    }
}

addMissingAttributes();
