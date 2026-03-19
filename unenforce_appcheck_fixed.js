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

        // Patch Identity Toolkit
        const serviceId = 'identitytoolkit.googleapis.com';
        const url = `https://firebaseappcheck.googleapis.com/v1/projects/${projectId}/services/${serviceId}?updateMask=enforcementMode`;

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

        const data = await response.json();
        console.log("Response:", JSON.stringify(data, null, 2));

    } catch (err) {
        console.error("Error executing script", err);
    }
}

unenforceAppCheck();
