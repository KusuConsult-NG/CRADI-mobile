const { google } = require('googleapis');
const fetch = require('node-fetch');

async function unenforceAppCheck() {
    const auth = new google.auth.GoogleAuth({
        scopes: ['https://www.googleapis.com/auth/firebase']
    });

    try {
        const client = await auth.getClient();
        const tokenResponse = await client.getAccessToken();
        const token = tokenResponse.token;

        const projectId = 'ewer-8f788';

        // Identity Toolkit's service identifier in App Check is typically identitytoolkit.googleapis.com
        const serviceId = 'identitytoolkit.googleapis.com';
        const url = `https://firebaseappcheck.googleapis.com/v1/projects/${projectId}/services/${serviceId}`;

        console.log(`Patching ${url} to unenforce App Check...`);

        const response = await fetch(url, {
            method: 'PATCH',
            headers: {
                'Authorization': `Bearer ${token}`,
                'Content-Type': 'application/json',
                'X-Goog-User-Project': projectId
            },
            body: JSON.stringify({
                enforcementMode: 'UNENFORCED'
            })
        });

        if (!response.ok) {
            const errorText = await response.text();
            console.error(`Failed: ${response.status} ${response.statusText}`);
            console.error(errorText);

            // If the above identifier fails, it might be listed differently. Let's try to query all services.
            console.log("\nQuerying all services to find the correct Identity Toolkit name...");
            const listUrl = `https://firebaseappcheck.googleapis.com/v1/projects/${projectId}/services`;
            const listResponse = await fetch(listUrl, {
                headers: { 'Authorization': `Bearer ${token}`, 'X-Goog-User-Project': projectId }
            });
            const listData = await listResponse.json();
            console.log(JSON.stringify(listData, null, 2));
            return;
        }

        const data = await response.json();
        console.log("Success! App Check unenforced for Identity Toolkit:");
        console.log(JSON.stringify(data, null, 2));

    } catch (err) {
        console.error("Error executing script", err);
    }
}

unenforceAppCheck();
