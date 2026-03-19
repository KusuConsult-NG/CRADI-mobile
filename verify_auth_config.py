import urllib.request
import urllib.error
import subprocess
import json

def get_token():
    result = subprocess.run(["gcloud", "auth", "print-access-token"], capture_output=True, text=True)
    return result.stdout.strip()

token = get_token()
project = "ewer-8f788"
url = f"https://identitytoolkit.googleapis.com/admin/v2/projects/{project}/config"

req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
try:
    with urllib.request.urlopen(req) as response:
        data = json.loads(response.read().decode())
        print(json.dumps(data, indent=2))
except urllib.error.URLError as e:
    print(f"Error: {e}")
