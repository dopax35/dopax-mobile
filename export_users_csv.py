import csv
import firebase_admin
from firebase_admin import credentials, auth, firestore

# 1. Initialize Firebase Admin SDK
cred = credentials.Certificate('serviceAccountKey.json')
firebase_admin.initialize_app(cred)

db = firestore.client()
output_filename = 'users_export.csv'

print("Fetching user data from Firebase Auth and Firestore...")

user_rows = []

# 2. Iterate through all Firebase Auth users
page = auth.list_users()
while page:
    for user in page.users:
        uid = user.uid
        email = user.email or ''
        phone = user.phone_number or ''
        name = user.display_name or ''

        # 3. Check Firestore 'users' document for extra profile fields (if present)
        firestore_data = {}
        try:
            doc = db.collection('users').document(uid).get()
            if doc.exists:
                firestore_data = doc.to_dict() or {}
        except Exception as e:
            print(f"Warning: Could not fetch Firestore doc for {uid}: {e}")

        # Extract values, preferring Firestore profile data if Auth missing
        full_name = (
            name 
            or firestore_data.get('signatureName') 
            or firestore_data.get('name') 
            or ''
        )
        user_email = email or firestore_data.get('email', '')
        user_phone = (
            phone 
            or firestore_data.get('phone') 
            or firestore_data.get('phoneNumber') 
            or ''
        )
        app_user_id = firestore_data.get('userId', '')  # App-specific ID reported with uploaded files

        user_rows.append({
            'uid': uid,
            'app_user_id': app_user_id,
            'name': full_name,
            'email': user_email,
            'phone': user_phone
        })

    # Fetch next batch of users if more than 1000 exist
    page = page.get_next_page()

# 4. Write to CSV
fieldnames = ['uid', 'app_user_id', 'name', 'email', 'phone']

with open(output_filename, mode='w', newline='', encoding='utf-8') as csv_file:
    writer = csv.DictWriter(csv_file, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(user_rows)

print(f"Done! Exported {len(user_rows)} users to '{output_filename}'.")