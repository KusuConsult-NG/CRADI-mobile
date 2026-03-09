const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const fs = require('fs');
const util = require('util');

async function runTest() {
    const projectId = "ewer-8f788-" + Date.now();
    console.log(`Testing with projectId: ${projectId}`);

    let testEnv = await initializeTestEnvironment({
        projectId: projectId,
        firestore: {
            rules: fs.readFileSync('firestore.rules', 'utf8'),
            host: 'localhost',
            port: 8080,
        },
    });

    // Mock authenticated user context
    const userId = 'live_test_user_uid';
    const alice = testEnv.authenticatedContext(userId, {
        email: 'test@example.com',
    });

    const payload = {
        email: 'test@example.com',
        name: 'Test User',
        role: 'user',
        address: '',
        state: '',
        lga: '',
        ward: '',
        isVerified: false,
        isApproved: false,
        biometricsEnabled: false,
        createdAt: new Date().toISOString(),
        lastLoginAt: new Date().toISOString(),
        phone: '',
        profileImageUrl: ''
    };

    try {
        console.log("Attempting to write doc...");
        await assertSucceeds(alice.firestore().collection('users').doc(userId).set(payload));
        console.log("Success! The payload passed the rules.");
    } catch (error) {
        console.error("Failed! The payload was rejected by the rules.");
        console.error(error.message);
    }

    await testEnv.cleanup();
}

runTest();
