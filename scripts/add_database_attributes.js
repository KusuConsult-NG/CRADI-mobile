#!/usr/bin/env node

/**
 * Appwrite Database Schema Migration Script
 * 
 * This script adds all missing attributes to the Appwrite database collections
 * based on the EWER Mobile app requirements.
 * 
 * Prerequisites:
 * - Node.js installed
 * - Run: npm install node-appwrite
 * - Appwrite API key with database permissions
 * 
 * Usage:
 * node scripts/add_database_attributes.js
 */

const sdk = require('node-appwrite');

// Configuration
const CONFIG = {
    endpoint: 'https://fra.cloud.appwrite.io/v1',
    projectId: '6941cdb400050e7249d5',
    databaseId: '6941e2c2003705bb5a25',
    apiKey: process.env.APPWRITE_API_KEY || '', // Set your API key as environment variable
};

// Collection IDs
const COLLECTIONS = {
    users: 'users',
    reports: 'reports',
    chats: 'chats',
    messages: 'messages',
    emergency_contacts: 'emergency_contacts',
    trusted_devices: 'trusted_devices',
    login_history: 'login_history',
    knowledge_base: 'knowledge_base',
};

// Schema definitions
const SCHEMAS = {
    users: [
        { key: 'email', type: 'string', size: 255, required: true, array: false },
        { key: 'name', type: 'string', size: 100, required: true, array: false },
        { key: 'role', type: 'string', size: 50, required: true, array: false },
        { key: 'address', type: 'string', size: 500, required: false, array: false },
        { key: 'biometricsEnabled', type: 'boolean', required: true, array: false, default: false },
        { key: 'createdAt', type: 'datetime', required: true, array: false },
        { key: 'lastLoginAt', type: 'datetime', required: false, array: false },
        { key: 'phoneNumber', type: 'string', size: 20, required: false, array: false },
        { key: 'profileImageId', type: 'string', size: 255, required: false, array: false },
    ],
    reports: [
        { key: 'userId', type: 'string', size: 255, required: true, array: false },
        { key: 'hazardType', type: 'string', size: 100, required: true, array: false },
        { key: 'severity', type: 'string', size: 50, required: true, array: false },
        { key: 'description', type: 'string', size: 2000, required: true, array: false },
        { key: 'location', type: 'string', size: 500, required: true, array: false },
        { key: 'latitude', type: 'double', required: true, array: false },
        { key: 'longitude', type: 'double', required: true, array: false },
        { key: 'state', type: 'string', size: 100, required: false, array: false },
        { key: 'lga', type: 'string', size: 100, required: false, array: false },
        { key: 'imageIds', type: 'string', size: 255, required: false, array: true },
        { key: 'status', type: 'string', size: 50, required: true, array: false },
        { key: 'createdAt', type: 'datetime', required: true, array: false },
        { key: 'updatedAt', type: 'datetime', required: false, array: false },
    ],
    emergency_contacts: [
        { key: 'userId', type: 'string', size: 255, required: true, array: false },
        { key: 'name', type: 'string', size: 100, required: true, array: false },
        { key: 'phone', type: 'string', size: 20, required: true, array: false },
        { key: 'relationship', type: 'string', size: 100, required: false, array: false },
        { key: 'organization', type: 'string', size: 200, required: false, array: false },
        { key: 'lga', type: 'string', size: 100, required: false, array: false },
        { key: 'category', type: 'string', size: 50, required: false, array: false },
        { key: 'isAvailable', type: 'boolean', required: false, array: false, default: true },
    ],
    chats: [
        { key: 'participants', type: 'string', size: 255, required: true, array: true },
        { key: 'lastMessage', type: 'string', size: 500, required: false, array: false },
        { key: 'lastMessageAt', type: 'datetime', required: false, array: false },
        { key: 'createdAt', type: 'datetime', required: true, array: false },
    ],
    messages: [
        { key: 'chatId', type: 'string', size: 255, required: true, array: false },
        { key: 'senderId', type: 'string', size: 255, required: true, array: false },
        { key: 'text', type: 'string', size: 2000, required: true, array: false },
        { key: 'createdAt', type: 'datetime', required: true, array: false },
        { key: 'readBy', type: 'string', size: 255, required: false, array: true },
    ],
    trusted_devices: [
        { key: 'userId', type: 'string', size: 255, required: true, array: false },
        { key: 'deviceId', type: 'string', size: 255, required: true, array: false },
        { key: 'deviceName', type: 'string', size: 200, required: false, array: false },
        { key: 'lastUsed', type: 'datetime', required: true, array: false },
        { key: 'createdAt', type: 'datetime', required: true, array: false },
    ],
    login_history: [
        { key: 'userId', type: 'string', size: 255, required: true, array: false },
        { key: 'deviceId', type: 'string', size: 255, required: false, array: false },
        { key: 'ipAddress', type: 'string', size: 50, required: false, array: false },
        { key: 'location', type: 'string', size: 200, required: false, array: false },
        { key: 'successful', type: 'boolean', required: true, array: false },
        { key: 'timestamp', type: 'datetime', required: true, array: false },
    ],
    knowledge_base: [
        { key: 'title', type: 'string', size: 200, required: true, array: false },
        { key: 'content', type: 'string', size: 10000, required: true, array: false },
        { key: 'category', type: 'string', size: 100, required: true, array: false },
        { key: 'tags', type: 'string', size: 50, required: false, array: true },
        { key: 'authorId', type: 'string', size: 255, required: false, array: false },
        { key: 'createdAt', type: 'datetime', required: true, array: false },
        { key: 'updatedAt', type: 'datetime', required: false, array: false },
    ],
};

async function main() {
    // Validate API key
    if (!CONFIG.apiKey) {
        console.error('❌ Error: APPWRITE_API_KEY environment variable not set');
        console.log('\nSet your API key:');
        console.log('  export APPWRITE_API_KEY="your-api-key-here"');
        console.log('\nOr run:');
        console.log('  APPWRITE_API_KEY="your-key" node scripts/add_database_attributes.js');
        process.exit(1);
    }

    // Initialize Appwrite client
    const client = new sdk.Client();
    const databases = new sdk.Databases(client);

    client
        .setEndpoint(CONFIG.endpoint)
        .setProject(CONFIG.projectId)
        .setKey(CONFIG.apiKey);

    console.log('🚀 Starting database schema migration...\n');
    console.log(`📊 Database: ${CONFIG.databaseId}`);
    console.log(`🔗 Endpoint: ${CONFIG.endpoint}\n`);

    let totalAdded = 0;
    let totalSkipped = 0;
    let totalErrors = 0;

    // Process each collection
    for (const [collectionName, schema] of Object.entries(SCHEMAS)) {
        const collectionId = COLLECTIONS[collectionName];

        console.log(`\n📁 Processing collection: ${collectionName} (${collectionId})`);
        console.log('─'.repeat(60));

        // Get existing attributes, create collection if it doesn't exist
        let existingAttributes = [];
        try {
            const collection = await databases.getCollection(
                CONFIG.databaseId,
                collectionId
            );
            existingAttributes = collection.attributes.map(attr => attr.key);
            console.log(`   Found ${existingAttributes.length} existing attributes`);
        } catch (error) {
            // Collection doesn't exist, create it
            console.log(`   ⚠️  Collection not found, creating: ${collectionId}`);
            try {
                await databases.createCollection(
                    CONFIG.databaseId,
                    collectionId,
                    collectionName.split('_').map(word =>
                        word.charAt(0).toUpperCase() + word.slice(1)
                    ).join(' '),
                    undefined, // permissions - will use database defaults
                    false, // documentSecurity - disabled for simplicity
                    true   // enabled
                );
                console.log(`   ✅ Created collection: ${collectionId}`);
                // Small delay after creating collection
                await new Promise(resolve => setTimeout(resolve, 1000));
            } catch (createError) {
                console.log(`   ❌ Failed to create collection: ${createError.message}`);
                totalErrors++;
                continue;
            }
        }

        // Add missing attributes
        for (const attribute of schema) {
            if (existingAttributes.includes(attribute.key)) {
                console.log(`   ⏭️  ${attribute.key} (${attribute.type}) - already exists`);
                totalSkipped++;
                continue;
            }

            try {
                // Create attribute based on type
                switch (attribute.type) {
                    case 'string':
                        await databases.createStringAttribute(
                            CONFIG.databaseId,
                            collectionId,
                            attribute.key,
                            attribute.size,
                            attribute.required,
                            attribute.default,
                            attribute.array
                        );
                        break;

                    case 'boolean':
                        await databases.createBooleanAttribute(
                            CONFIG.databaseId,
                            collectionId,
                            attribute.key,
                            attribute.required,
                            attribute.default,
                            attribute.array
                        );
                        break;

                    case 'integer':
                        await databases.createIntegerAttribute(
                            CONFIG.databaseId,
                            collectionId,
                            attribute.key,
                            attribute.required,
                            attribute.min,
                            attribute.max,
                            attribute.default,
                            attribute.array
                        );
                        break;

                    case 'double':
                    case 'float':
                        await databases.createFloatAttribute(
                            CONFIG.databaseId,
                            collectionId,
                            attribute.key,
                            attribute.required,
                            attribute.min,
                            attribute.max,
                            attribute.default,
                            attribute.array
                        );
                        break;

                    case 'datetime':
                        await databases.createDatetimeAttribute(
                            CONFIG.databaseId,
                            collectionId,
                            attribute.key,
                            attribute.required,
                            attribute.default,
                            attribute.array
                        );
                        break;

                    default:
                        console.log(`   ❌ Unknown type: ${attribute.type} for ${attribute.key}`);
                        totalErrors++;
                        continue;
                }

                console.log(`   ✅ Added: ${attribute.key} (${attribute.type})`);
                totalAdded++;

                // Small delay to avoid rate limiting
                await new Promise(resolve => setTimeout(resolve, 200));

            } catch (error) {
                console.log(`   ❌ Failed to add ${attribute.key}: ${error.message}`);
                totalErrors++;
            }
        }
    }

    // Summary
    console.log('\n' + '='.repeat(60));
    console.log('📊 MIGRATION SUMMARY');
    console.log('='.repeat(60));
    console.log(`✅ Attributes added:   ${totalAdded}`);
    console.log(`⏭️  Attributes skipped: ${totalSkipped}`);
    console.log(`❌ Errors:             ${totalErrors}`);
    console.log('='.repeat(60));

    if (totalAdded > 0) {
        console.log('\n✨ Database schema updated successfully!');
        console.log('💡 Note: Attributes may take a few moments to be fully available');
    }

    if (totalErrors > 0) {
        console.log('\n⚠️  Some operations failed. Please check the errors above.');
        process.exit(1);
    }
}

// Run the script
main().catch((error) => {
    console.error('\n❌ Fatal error:', error.message);
    process.exit(1);
});
