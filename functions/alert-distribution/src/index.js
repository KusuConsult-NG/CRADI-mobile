const sdk = require('node-appwrite');

/**
 * Alert Distribution Function
 * 
 * Trigger: databases.*.collections.reports.documents.*.update
 * Logic:
 * 1. Checks if status changed to 'validated'
 * 2. Fetches authority contacts for the report's LGA/State
 * 3. Sends SMS via Africa's Talking
 * 4. Sends Push Notifications via Appwrite Messaging (or FCM)
 */

module.exports = async ({ req, res, log, error }) => {
    const client = new sdk.Client()
        .setEndpoint(process.env.APPWRITE_FUNCTION_ENDPOINT)
        .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
        .setKey(process.env.APPWRITE_API_KEY);

    const databases = new sdk.Databases(client);
    const messaging = new sdk.Messaging(client);

    const DATABASE_ID = process.env.DATABASE_ID;
    const AUTHORITIES_COLLECTION_ID = process.env.AUTHORITIES_COLLECTION_ID;
    const AT_API_KEY = process.env.AFRICASTALKING_API_KEY;
    const AT_USERNAME = process.env.AFRICASTALKING_USERNAME;
    const AT_SENDER_ID = process.env.AFRICASTALKING_SENDER_ID || 'CRADI';

    try {
        const report = JSON.parse(req.payload);

        // Only proceed if status is 'validated'
        if (report.status !== 'validated') {
            return res.json({ success: true, message: 'Status is not validated. Skipping.' });
        }

        log(`Distributing alerts for validated report: ${report.$id} (${report.hazardType})`);

        // 1. Fetch Authorities for this LGA & State
        const authResponse = await databases.listDocuments(
            DATABASE_ID,
            AUTHORITIES_COLLECTION_ID,
            [
                sdk.Query.equal('state', report.state),
                sdk.Query.equal('lga', report.lga)
            ]
        );

        const authorityPhones = authResponse.documents.map(a => a.phone);
        log(`Found ${authorityPhones.length} authority contacts.`);

        // 2. Prepare Alert Message
        const alertMessage = `🚨 CRADI ALERT: ${report.severity.toUpperCase()} ${report.hazardType} reported in ${report.ward}, ${report.lga}. Safety: ${report.description.substring(0, 100)}`;

        // 3. Send SMS via Africa's Talking (using global fetch in Node 18)
        if (authorityPhones.length > 0 && AT_API_KEY && AT_USERNAME) {
            try {
                const atResponse = await fetch('https://api.africastalking.com/version1/messaging', {
                    method: 'POST',
                    headers: {
                        'Accept': 'application/json',
                        'Content-Type': 'application/x-www-form-urlencoded',
                        'apiKey': AT_API_KEY
                    },
                    body: new URLSearchParams({
                        username: AT_USERNAME,
                        to: authorityPhones.join(','),
                        message: alertMessage,
                        from: AT_SENDER_ID
                    })
                });
                const atResult = await atResponse.json();
                log('SMS distribution result:', JSON.stringify(atResult));
            } catch (e) {
                error(`SMS distribution failed: ${e.message}`);
            }
        }

        // 4. Send Push Notifications (Topic-based if supported, or targeted)
        // Here we send to a topic named after the LGA or State
        try {
            await messaging.createPush(
                sdk.ID.unique(),
                alertMessage,
                [], // Target users
                [], // Target slots
                [report.lga.replace(/\s+/g, '_').toLowerCase(), report.state.toLowerCase()], // Topics
                report.hazardType, // Title
                alertMessage, // Body
                null, // Data
                null, // Action
                null, // Icon
                null, // Sound
                null, // Color
                null, // Tag
                null, // Badge
                null  // Image
            );
            log('Push notification sent to topics.');
        } catch (e) {
            error(`Push notification failed: ${e.message}`);
        }

        return res.json({ success: true });

    } catch (err) {
        error(`Alert Distribution error: ${err.message}`);
        return res.json({ success: false, error: err.message }, 500);
    }
};
