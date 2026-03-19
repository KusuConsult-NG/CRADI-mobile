const admin = require('firebase-admin');

async function main() {
  // Initialize the SDK using Google Application Default Credentials
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: 'ewer-8f788'
  });

  try {
    const appCheck = admin.appCheck();
    
    // The appId for the Identity Toolkit / Auth service is technically the Project ID in some contexts, 
    // but App Check enforcement is usually per-app. However, we can try to get the current services.
    // Let's try to list all services and unenforce them.
    
    // Identity Toolkit doesn't have a standard App ID like Android/iOS apps. 
    // It's a "service" in the App Check context.
    // We will use the REST API approach for App Check Services directly if the Admin SDK doesn't natively expose `setServiceConfig`
    
    console.log("Attempting to unenforce App Check via REST API since Admin SDK focuses on Apps, not Backend Services...");
  } catch (error) {
    console.error("ERROR:", error);
  }
}

main();
