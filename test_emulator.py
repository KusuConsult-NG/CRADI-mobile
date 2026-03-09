import requests
import json
import os

from dotenv import load_dotenv

# Load from .env
load_dotenv('.env')

API_KEY = "dummy"

# 1. Sign up new user (Bypassed since we are using emulator auth)
# For the emulator, we don't need to actually sign up via Identity Toolkit if we just spoof the token in the Firestore REST call, but let's try to hit the emulator's auth endpoint if it's running. Since we only started firestore, we'll spoof the token.
local_id = "testuser_123"

# Spoofing an unsigned JWT for the emulator
# The emulator accepts unsigned JWTs if the header alg is "none"
import base64
header = base64.b64encode(b'{"alg":"none","typ":"JWT"}').decode('utf-8')
payload = base64.b64encode(b'{"iss":"https://securetoken.google.com/ewer-8f788","aud":"ewer-8f788","auth_time":1615000000,"user_id":"testuser_123","sub":"testuser_123","iat":1615000000,"exp":1930500000,"email":"mock@example.com","email_verified":true,"firebase":{"identities":{"email":["mock@example.com"]},"sign_in_provider":"password"}}').decode('utf-8')
id_token = f"{header}.{payload}."

print(f"Spoofed User created: {local_id}")

# 2. Add to firestore manually
firestore_url = f"http://127.0.0.1:8080/v1/projects/ewer-8f788/databases/(default)/documents/users/{local_id}?key={API_KEY}"
headers = {
    "Authorization": f"Bearer {id_token}",
    "Content-Type": "application/json"
}

# Matching exactly what the Flutter app sends
doc_payload = {
    "fields": {
        "email": {"stringValue": "test_local@example.com"},
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
print(f"Firestore Create Response: {db_response.status_code} - {db_response.text}")
