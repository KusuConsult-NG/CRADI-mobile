const sdk = require('node-appwrite');

/**
 * Escalation Timer Function
 * 
 * Scheduled: Every 5 minutes (*/5 * * * *)
 * Logic: 
 * 1. Queries reports with status 'pending'
    * 2. Filters those where 'submittedAt' is older than 30 minutes
        * 3. Updates status to 'escalated' and notifies coordinators
            */

module.exports = async ({ req, res, log, error }) => {
    const client = new sdk.Client()
        .setEndpoint(process.env.APPWRITE_FUNCTION_ENDPOINT)
        .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
        .setKey(process.env.APPWRITE_API_KEY);

    const databases = new sdk.Databases(client);
    const DATABASE_ID = process.env.DATABASE_ID;
    const REPORTS_COLLECTION_ID = process.env.REPORTS_COLLECTION_ID;

    try {
        log('Checking for reports requiring escalation...');

        // 30 minutes in milliseconds
        const thirtyMinutesAgo = new Date(Date.now() - 30 * 60 * 1000).toISOString();

        // Get pending reports submitted > 30 mins ago that aren't already escalated
        const response = await databases.listDocuments(
            DATABASE_ID,
            REPORTS_COLLECTION_ID,
            [
                sdk.Query.equal('status', 'pending'),
                sdk.Query.lessThan('submittedAt', thirtyMinutesAgo),
                sdk.Query.limit(100) // Process in chunks
            ]
        );

        log(`Found ${response.documents.length} reports to process.`);

        const updates = response.documents.map(async (report) => {
            try {
                await databases.updateDocument(
                    DATABASE_ID,
                    REPORTS_COLLECTION_ID,
                    report.$id,
                    {
                        status: 'escalated',
                        escalatedAt: new Date().toISOString(),
                        escalationReason: 'Peer verification timeout (30m)'
                    }
                );
                log(`Escalated report ${report.$id}`);
            } catch (e) {
                error(`Failed to update report ${report.$id}: ${e.message}`);
            }
        });

        await Promise.all(updates);

        return res.json({
            success: true,
            processed: response.documents.length
        });

    } catch (err) {
        error(`Escalation function error: ${err.message}`);
        return res.json({ success: false, error: err.message }, 500);
    }
};
