import urllib.request
import urllib.error
import json
import google.auth
from google.auth.transport.requests import Request

def register_debug_token():
    try:
        # Get default credentials (works via gcloud locally)
        credentials, _ = google.auth.default(scopes=['https://www.googleapis.com/auth/cloud-platform'])
        credentials.refresh(Request())
        
        project_id = "ewer-8f788"
        app_id = "1:689251502200:android:3c102d339da6c4437e458d"
        token = "43f3d955-60b2-4d4f-b449-94e9e0e16828"
        
        url = f"https://firebaseappcheck.googleapis.com/v1/projects/{project_id}/apps/{app_id}/debugTokens"
        
        headers = {
            "Authorization": f"Bearer {credentials.token}",
            "Content-Type": "application/json",
            "x-goog-user-project": project_id
        }
        
        data = {
            "displayName": "Local Emulator Agent Auto",
            "token": token
        }
        
        req = urllib.request.Request(url, data=json.dumps(data).encode('utf-8'), headers=headers, method='POST')
        
        try:
            with urllib.request.urlopen(req) as response:
                result = response.read().decode('utf-8')
                print(f"Successfully added debug token!\nResponse: {result}")
        except urllib.error.HTTPError as e:
            error_msg = e.read().decode('utf-8')
            print(f"HTTPError ({e.code}): {error_msg}")
    except Exception as e:
        print(f"Failed to register token: {e}")

if __name__ == '__main__':
    register_debug_token()
