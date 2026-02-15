const sdk = require('node-appwrite');

// Configuration
const CONFIG = {
    endpoint: process.env.APPWRITE_ENDPOINT || 'https://fra.cloud.appwrite.io/v1',
    projectId: process.env.APPWRITE_PROJECT_ID || '6941cdb400050e7249d5',
    databaseId: process.env.DATABASE_ID || '6941e2c2003705bb5a25',
    apiKey: process.env.APPWRITE_API_KEY,
};

async function createStatisticsCollection() {
    if (!CONFIG.apiKey) {
        console.error('❌ Error: APPWRITE_API_KEY environment variable is required');
        console.log('\nUsage:');
        console.log('  APPWRITE_API_KEY=your_key node scripts/create_statistics_collection.js');
        process.exit(1);
    }

    console.log('📊 Creating Statistics Collection\n');
    console.log(`Project ID: ${CONFIG.projectId}`);
    console.log(`Database ID: ${CONFIG.databaseId}\n`);

    const client = new sdk.Client()
        .setEndpoint(CONFIG.endpoint)
        .setProject(CONFIG.projectId)
        .setKey(CONFIG.apiKey);

    const databases = new sdk.Databases(client);

    try {
        // Check if collection already exists
        try {
            const existing = await databases.getCollection(CONFIG.databaseId, 'statistics');
            console.log('✅ Statistics collection already exists');
            console.log(`   Collection ID: ${existing.$id}`);
            console.log(`   Total attributes: ${existing.attributes.length}`);
            return;
        } catch (e) {
            if (e.code !== 404) {
                throw e;
            }
            console.log('Creating new statistics collection...');
        }

        // Create the collection
        const collection = await databases.createCollection(
            CONFIG.databaseId,
            'statistics',
            'Statistics',
            [
                sdk.Permission.read(sdk.Role.any()),
                sdk.Permission.create(sdk.Role.label('admin')),
                sdk.Permission.update(sdk.Role.label('admin')),
                sdk.Permission.delete(sdk.Role.label('admin')),
            ],
            false // documentSecurity = false
        );

        console.log('✅ Collection created:', collection.$id);

        // Create attributes
        console.log('\n📝 Creating attributes...');

        // timestamp
        await databases.createStringAttribute(
            CONFIG.databaseId,
            'statistics',
            'timestamp',
            255,
            true // required
        );
        console.log('  ✅ timestamp (string)');

        // Wait a bit for attribute to be ready
        await new Promise(resolve => setTimeout(resolve, 1000));

        // totalCount
        await databases.createIntegerAttribute(
            CONFIG.databaseId,
            'statistics',
            'totalCount',
            true, // required
            0, // min
            999999999, // max
            0 // default
        );
        console.log('  ✅ totalCount (integer)');

        await new Promise(resolve => setTimeout(resolve, 1000));

        // validatedCount
        await databases.createIntegerAttribute(
            CONFIG.databaseId,
            'statistics',
            'validatedCount',
            true,
            0,
            999999999,
            0
        );
        console.log('  ✅ validatedCount (integer)');

        await new Promise(resolve => setTimeout(resolve, 1000));

        // escalatedCount
        await databases.createIntegerAttribute(
            CONFIG.databaseId,
            'statistics',
            'escalatedCount',
            true,
            0,
            999999999,
            0
        );
        console.log('  ✅ escalatedCount (integer)');

        console.log('\n✅ Statistics collection created successfully!');
        console.log('\nCollection Details:');
        console.log(`  ID: statistics`);
        console.log(`  Name: Statistics`);
        console.log(`  Attributes: 4 (timestamp, totalCount, validatedCount, escalatedCount)`);
        console.log(`  Permissions: Public read, admin-only write`);

    } catch (error) {
        console.error(`\n❌ Error: ${error.message}`);
        if (error.response) {
            console.error('Response:', error.response);
        }
        process.exit(1);
    }
}

createStatisticsCollection();
