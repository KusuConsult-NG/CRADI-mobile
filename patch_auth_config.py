import requests
import subprocess
import json

def get_token():
    result = subprocess.run(["gcloud", "auth", "print-access-token"], capture_output=True, text=True)
    return result.stdout.strip()

token = get_token()
project = "ewer-8f788"
url = f"https://identitytoolkit.googleapis.com/admin/v2/projects/{project}/config?updateMask=emailPrivacyConfig"

headers = {
    "Authorization": f"Bearer {token}",
    "Content-Type": "application/json"
}

body = {
    "emailPrivacyConfig": {
        "enableImprovedEmailPrivacy": False
    }
}

response = requests.patch(url, headers=headers, json=body)
print(f"Status Code: {response.status_code}")
print("Response JSON:")
print(json.dumps(response.json(), indent=2))

