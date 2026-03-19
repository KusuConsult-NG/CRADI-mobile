const admin = require('firebase-admin');

async function main() {
    admin.initializeApp({
        credential: admin.credential.applicationDefault()
    });

    try {
        const auth = admin.auth();
        const projectConfig = await auth.projectConfigManager().updateProjectConfig({
            emailPrivacyConfig: {
                enableImprovedEmailPrivacy: false
            }
        });
        console.log("SUCCESS: Email Enumeration Protection set to", projectConfig.emailPrivacyConfig.enableImprovedEmailPrivacy);
    } catch (error) {
        console.error("ERROR:", error);
    }
}

main();
