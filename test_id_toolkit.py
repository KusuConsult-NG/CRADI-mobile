import requests
import google.auth
from google.auth.transport.requests import Request

def get_auth_config():
    credentials, project_id = google.auth.default()
    credentials.refresh(Request())
    
    url = f"https://identitytoolkit.googleapis.com/v2/projects/{project_id}/config"
    headers = {
        "Authorization": f"Bearer {credentials.token}"
    }
    
    response = requests.get(url, headers=headers)
    print(f"Status: {response.status_code}")
    print(response.json())

get_auth_config()
