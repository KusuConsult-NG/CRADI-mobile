import firebase_admin
from firebase_admin import credentials, firestore

def main():
    try:
        cred = credentials.ApplicationDefault()
        app = firebase_admin.initialize_app(cred, {
            'projectId': 'ewer-8f788',
        })
        
        db = firestore.client()
        uid = "zVLIr4coqJMncnIV4meoFJwHH0t2"
        
        doc_ref = db.collection('users').document(uid)
        doc = doc_ref.get()
        if doc.exists:
            print(f"Current role: {doc.to_dict().get('role')}")
            doc_ref.update({'role': 'admin'})
            print(f"Successfully updated role to 'admin' for user {uid}")
        else:
            print(f"User document for {uid} does not exist!")
    except Exception as e:
        print(f"Error: {e}")

if __name__ == '__main__':
    main()
