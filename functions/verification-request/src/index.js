const sdk = require('node-appwrite');

/**
 * Verification Request Function
 * 
 * Trigger: databases.*.collections.reports.documents.*.create
 * Logic:
 * 1. Identifies the ward and LGA of the new report.
 * 2. Finds other users (EWMs) in the same ward.
 * 3. Sends a notification (Verification Request) to them.
 */

module.exports = async ({ req, res, log, error }) => {
    const client = new sdk.Client()
        .setEndpoint(process.env.APPWRITE_FUNCTION_ENDPOINT)
        .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
        .setKey(process.env.APPWRITE_API_KEY);

    const databases = new sdk.Databases(client);
    const messaging = new sdk.Messaging(client);

    const DATABASE_ID = process.env.DATABASE_ID;
    const USERS_COLLECTION_ID = process.env.USERS_COLLECTION_ID;

    try {
        const report = JSON.parse(req.payload);

        log(`New report created: ${report.$id}. Notifying peers in ward: ${report.ward}`);

        // 1. Fetch Users in the same Ward, excluding the reporter
        const response = await databases.listDocuments(
            DATABASE_ID,
            USERS_COLLECTION_ID,
            [
                sdk.Query.equal('ward', report.ward),
                sdk.Query.equal('lga', report.lga),
                sdk.Query.notEqual('$id', report.userId), // Assuming userId is stored in report
                sdk.Query.limit(50)
            ]
        );

        const peerUserIds = response.documents.map(d => d.$id);
        log(`Found ${peerUserIds.length} peers in ward.`);

        if (peerUserIds.length === 0) {
            log('No peers found for verification.');
            return res.json({ success: true, message: 'No peers found.' });
        }

        // 2. Send Push Notification to Peers
        const notificationMessage = `🔍 Action Required: New ${report.hazardType} report in ${report.ward} needs your verification.`;

        try {
            await messaging.createPush(
                sdk.ID.unique(),
                notificationMessage,
                peerUserIds, // Target the specific peers
                [], // Target slots
                [], // Topics
                'Verify Report', // Title
                notificationMessage,
                {
                    type: 'verification_request',
                    reportId: report.$id
                }
            );
            log('Verification push notifications sent to peers.');
        } catch (e) {
            error(`Failed to send verification push: ${e.message}`);
        }

        return res.json({ success: true });

    } catch (err) {
        error(`Verification Request error: ${err.message}`);
        return res.json({ success: false, error: err.message }, 500);
    }
};
