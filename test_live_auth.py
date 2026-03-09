import requests
import json
import time

def main():
    try:
        with open('test_register.py', 'r') as f:
            content = f.read()
            import re
            match = re.search(r'API_KEY\s*=\s*"([^"]+)"', content)
            if not match:
                print("Could not find API_KEY")
                return
            API_KEY = match.group(1)
            
        email = f"live_test_{int(time.time())}@example.com"
        password = "Password123"
        
        print(f"Testing signup for {email}")
        
        url = f"https://identitytoolkit.googleapis.com/v1/accounts:signUp?key={API_KEY}"
        payload = {
            "email": email,
            "password": password,
            "returnSecureToken": True
        }
        
        response = requests.post(url, json=payload, timeout=10)
        print(f"Auth Response Code: {response.status_code}")
        print(f"Auth Response Body: {response.text}")
        
        if response.status_code == 200:
            data = response.json()
            id_token = data.get("idToken")
            uid = data.get("localId")
            print(f"Logged in implicitly as UID: {uid}")
            
            firestore_url = f"https://firestore.googleapis.com/v1/projects/ewer-8f788/databases/(default)/documents/users/{uid}"
            
            doc_payload = {
                "fields": {
                    "uid": {"stringValue": uid},
                    "email": {"stringValue": email},
                    "role": {"stringValue": "user"}
                }
            }
            
            headers = {
                "Authorization": f"Bearer {id_token}",
                "Content-Type": "application/json"
            }
            
            print("Writing to Firestore...")
            fs_response = requests.patch(firestore_url, headers=headers, json=doc_payload, timeout=10)
            print(f"Firestore Response Code: {fs_response.status_code}")
            print(f"Firestore Response Body: {fs_response.text}")
    except Exception as e:
        print(f"Exception occurred: {e}")

if __name__ == "__main__":
    main()
