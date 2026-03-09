import google.auth
from google.auth.transport.requests import Request
import requests
import json

def register_debug_token(project_id, app_id, token_string, display_name):
    # Get credentials
    credentials, project = google.auth.default(
        scopes=["https://www.googleapis.com/auth/cloud-platform"]
    )
    
    # Refresh credentials to get a valid token
    credentials.refresh(Request())
    access_token = credentials.token
    
    # App Check API Endpoint
    # We want to create a new DebugToken
    url = f"https://firebaseappcheck.googleapis.com/v1/projects/{project_id}/apps/{app_id}/debugTokens"
    
    headers = {
        "Authorization": f"Bearer {access_token}",
        "Content-Type": "application/json"
    }
    
    data = {
        "displayName": display_name,
        "token": token_string
    }
    
    response = requests.post(url, headers=headers, json=data)
    print("Status:", response.status_code)
    print("Response:", response.text)

if __name__ == "__main__":
    # From firebase.json: 
    # Android App ID: 1:689251502200:android:3c102d339da6c4437e458d
    register_debug_token(
        "ewer-8f788", 
        "1:689251502200:android:3c102d339da6c4437e458d", 
        "22442d99-402d-4c3e-9cc9-5a834cec50cf",
        "Automated Emulator Fix"
    )
