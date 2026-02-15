const sdk = require('node-appwrite');

/**
 * Email Alert Distribution Function
 * 
 * Trigger: databases.*.collections.reports.documents.*.update
 * 
 * Sends email notifications to authorities when reports are validated.
 * Replaces SMS-based alert system with email-only notifications.
 */

module.exports = async ({ req, res, log, error }) => {
    const client = new sdk.Client()
        .setEndpoint(process.env.APPWRITE_FUNCTION_ENDPOINT)
        .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
        .setKey(process.env.APPWRITE_API_KEY);

    const databases = new sdk.Databases(client);
    const messaging = new sdk.Messaging(client);

    const DATABASE_ID = process.env.DATABASE_ID;
    const AUTHORITIES_COLLECTION_ID = process.env.AUTHORITIES_COLLECTION_ID || 'authorities';

    try {
        const report = JSON.parse(req.payload);

        // Only process validated reports
        if (report.status !== 'validated') {
            log(`Report ${report.$id} status is '${report.status}', not sending alerts`);
            return res.json({ success: true, message: 'Status not validated. Skipped.' });
        }

        log(`Processing validated report: ${report.$id} (${report.hazardType})`);

        // Fetch authorities for this location
        const authResponse = await databases.listDocuments(
            DATABASE_ID,
            AUTHORITIES_COLLECTION_ID,
            [
                sdk.Query.equal('state', report.state),
                sdk.Query.equal('lga', report.lga)
            ]
        );

        const authorities = authResponse.documents;
        const authorityEmails = authorities.map(a => a.email).filter(Boolean);

        log(`Found ${authorities.length} authorities, ${authorityEmails.length} with emails`);

        if (authorityEmails.length === 0) {
            log('No authority emails found for this location');
            return res.json({
                success: true,
                message: 'No authority emails found',
                authoritiesFound: authorities.length
            });
        }

        // Prepare email content
        const emailSubject = `[CRADI ALERT] ${report.severity.toUpperCase()} ${report.hazardType} - ${report.lga}`;

        const emailBody = `
CRADI DISASTER ALERT

Severity: ${report.severity.toUpperCase()}
Hazard Type: ${report.hazardType}

Location Details:
- Ward: ${report.ward}
- LGA: ${report.lga}
- State: ${report.state}

Description:
${report.description}

${report.recommendations ? `Recommendations:\n${report.recommendations}\n` : ''}

Reported: ${new Date(report.$createdAt).toLocaleString('en-US', {
            dateStyle: 'full',
            timeStyle: 'short'
        })}

Validated: ${new Date(report.$updatedAt).toLocaleString('en-US', {
            dateStyle: 'full',
            timeStyle: 'short'
        })}

---
This is an automated alert from the Climate Risk & Disaster Intelligence (CRADI) system.
Please take appropriate action as per your emergency response protocols.
        `.trim();

        // Send emails to all authorities
        let emailsSent = 0;
        let emailsFailed = 0;

        for (const email of authorityEmails) {
            try {
                // Using Appwrite's send-email function
                const emailResponse = await fetch(
                    `${process.env.APPWRITE_FUNCTION_ENDPOINT}/functions/send-email/executions`,
                    {
                        method: 'POST',
                        headers: {
                            'X-Appwrite-Project': process.env.APPWRITE_FUNCTION_PROJECT_ID,
                            'X-Appwrite-Key': process.env.APPWRITE_API_KEY,
                            'Content-Type': 'application/json'
                        },
                        body: JSON.stringify({
                            to: email,
                            subject: emailSubject,
                            body: emailBody,
                            template: 'alert',
                            data: {
                                hazardType: report.hazardType,
                                severity: report.severity,
                                ward: report.ward,
                                lga: report.lga,
                                state: report.state,
                                description: report.description,
                                recommendations: report.recommendations || '',
                                reportedAt: report.$createdAt,
                                validatedAt: report.$updatedAt
                            }
                        })
                    }
                );

                if (emailResponse.ok) {
                    emailsSent++;
                    log(`Email sent to: ${email}`);
                } else {
                    emailsFailed++;
                    const errorText = await emailResponse.text();
                    error(`Failed to send email to ${email}: ${errorText}`);
                }
            } catch (e) {
                emailsFailed++;
                error(`Email send error for ${email}: ${e.message}`);
            }
        }

        // Send push notifications to affected areas
        try {
            const topics = [
                report.lga.replace(/\s+/g, '_').toLowerCase(),
                report.state.toLowerCase().replace(/\s+/g, '_')
            ];

            const pushTitle = `${report.severity.toUpperCase()} ${report.hazardType}`;
            const pushBody = `${report.hazardType} reported in ${report.ward}, ${report.lga}. Stay safe!`;

            await messaging.createPush(
                sdk.ID.unique(),
                pushBody,
                [], // userIds
                [], // targets
                topics, // topics
                pushTitle, // title
                pushBody, // body
                { reportId: report.$id }, // data
                null, // action
                null, // icon
                null, // sound
                null, // color
                null, // tag
                null  // badge
            );

            log(`Push notifications sent to topics: ${topics.join(', ')}`);
        } catch (e) {
            error(`Push notification error: ${e.message}`);
            // Non-critical - continue even if push fails
        }

        // Summary
        const summary = {
            success: true,
            reportId: report.$id,
            hazardType: report.hazardType,
            severity: report.severity,
            location: `${report.ward}, ${report.lga}, ${report.state}`,
            authoritiesFound: authorities.length,
            emailsSent,
            emailsFailed,
            totalRecipients: authorityEmails.length
        };

        log(`Alert distribution complete: ${emailsSent}/${authorityEmails.length} emails sent`);
        return res.json(summary);

    } catch (err) {
        error(`Alert distribution error: ${err.message}`);
        error(`Stack: ${err.stack}`);
        return res.json({
            success: false,
            error: err.message
        }, 500);
    }
};
