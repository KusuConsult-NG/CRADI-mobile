import firebase_admin
from firebase_admin import credentials, auth, firestore

def delete_collection(coll_ref, batch_size):
    docs = coll_ref.limit(batch_size).stream()
    deleted = 0

    for doc in docs:
        print(f'Deleting doc {doc.id} => {doc.to_dict()}')
        doc.reference.delete()
        deleted = deleted + 1

    if deleted >= batch_size:
        return delete_collection(coll_ref, batch_size)

def main():
    try:
        cred = credentials.ApplicationDefault()
        app = firebase_admin.initialize_app(cred, {
            'projectId': 'ewer-8f788',
        })
        
        db = firestore.client()
        
        print("Clearing Firestore users collection...")
        delete_collection(db.collection('users'), 50)
        
        print("Clearing Firestore otp_verifications collection...")
        delete_collection(db.collection('otp_verifications'), 50)
        
        print("Clearing Firebase Auth users...")
        page = auth.list_users()
        count = 0
        while page:
            for user in page.users:
                auth.delete_user(user.uid)
                count += 1
            page = page.get_next_page()
            
        print(f"Successfully deleted {count} users from Auth.")
        print("Database cleared completely.")
    except Exception as e:
        print(f"Error: {e}")

if __name__ == '__main__':
    main()
