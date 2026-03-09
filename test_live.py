import requests
import json

API_KEY = "AIzaSyC1UtBDV_bO2Qbyz3vOihDCs747lM3ASCM"

# 1. Sign up new user
signup_url = f"https://identitytoolkit.googleapis.com/v1/accounts:signUp?key={API_KEY}"
signup_payload = {
    "email": "test_live_rule9@example.com",
    "password": "Password123!",
    "returnSecureToken": True
}
response = requests.post(signup_url, json=signup_payload)
print(f"Signup Base Response: {response.status_code}")

if response.status_code == 200:
    data = response.json()
    id_token = data['idToken']
    local_id = data['localId']
    print(f"User created: {local_id}")
    
    # 2. Add to firestore
    firestore_url = f"https://firestore.googleapis.com/v1/projects/ewer-8f788/databases/(default)/documents/users/{local_id}?key={API_KEY}"
    headers = {
        "Authorization": f"Bearer {id_token}",
        "Content-Type": "application/json"
    }
    
    # Matching exactly what the Flutter app sends
    doc_payload = {
        "fields": {
            "email": {"stringValue": "test_live_rule9@example.com"},
            "name": {"stringValue": "Test User"},
            "role": {"stringValue": "user"},
            "address": {"stringValue": ""},
            "state": {"stringValue": ""},
            "lga": {"stringValue": ""},
            "ward": {"stringValue": ""},
            "isVerified": {"booleanValue": False},
            "isApproved": {"booleanValue": False},
            "biometricsEnabled": {"booleanValue": False},
            "createdAt": {"stringValue": "2026-03-07T15:00:00Z"},
            "lastLoginAt": {"stringValue": "2026-03-07T15:00:00Z"},
            "phone": {"stringValue": ""},
            "profileImageUrl": {"stringValue": ""}
        }
    }
    
    db_response = requests.patch(firestore_url, headers=headers, json=doc_payload)
    print(f"Firestore Create Response: {db_response.status_code}")
    print(f"Error Details: {db_response.text}")
