const admin = require('firebase-admin');

// Initialize the app with default credentials
admin.initializeApp({
    projectId: 'ewer-8f788',
});

async function getCustomAppCheckToken() {
    try {
        const appCheckToken = await admin.appCheck().createToken('1:708226079948:android:d45082163351d14e918c50');
        console.log(appCheckToken.token);
    } catch (error) {
        console.error('Error creating custom App Check token:', error);
    }
}

getCustomAppCheckToken();
