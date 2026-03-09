import firebase_admin
from firebase_admin import credentials
from firebase_admin import firestore
import json

# This assumes we are authenticated with gcloud or have default credentials
# Let's try to initialize the default app
try:
    cred = credentials.ApplicationDefault()
    app = firebase_admin.initialize_app(cred, {
        'projectId': 'ewer-8f788',
    })
    
    db = firestore.client()

    doc_ref = db.collection('users').document('admin_sdk_test_uid')
    doc_ref.set({
        'email': 'admin@example.com',
        'name': 'Admin User',
        'role': 'user',
        'address': '',
        'state': '',
        'lga': '',
        'ward': '',
        'isVerified': False,
        'isApproved': False,
        'biometricsEnabled': False,
        'createdAt': '2026-03-07T15:00:00Z',
        'lastLoginAt': '2026-03-07T15:00:00Z',
        'phone': '',
        'profileImageUrl': ''
    })
    print("Successfully wrote document using Admin SDK.")
except Exception as e:
    print(f"Error using Admin SDK: {e}")
