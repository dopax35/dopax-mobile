import os
import json
import csv
import urllib.request

print("Locating Firebase CLI authentication token...")

user_profile = os.environ.get('USERPROFILE', '')
appdata = os.environ.get('APPDATA', '')

# Firebase CLI token paths on Windows
token_paths = [
    os.path.join(appdata, 'configstore', 'firebase-tools.json'),
    os.path.join(user_profile, '.config', 'configstore', 'firebase-tools.json'),
]

access_token = None
for path in token_paths:
    if os.path.exists(path):
        try:
            with open(path, 'r', encoding='utf-8') as f:
                config = json.load(f)
                tokens = config.get('tokens', {})
                access_token = tokens.get('access_token')
                if access_token:
                    break
        except Exception:
            pass

if not access_token:
    print("Error: Could not find active Firebase CLI token.")
    print("Please run: npx firebase-tools login --reauth")
    exit(1)

project_id = 'dopa-x-app'
print("Fetching user profiles from Firestore REST API...")

url = f"https://firestore.googleapis.com/v1/projects/{project_id}/databases/(default)/documents/users?pageSize=500"
req = urllib.request.Request(url, headers={'Authorization': f'Bearer {access_token}'})

firestore_map = {}
try:
    with urllib.request.urlopen(req) as response:
        res_data = json.loads(response.read().decode('utf-8'))
        documents = res_data.get('documents', [])
        for doc in documents:
            doc_name = doc.get('name', '')
            uid = doc_name.split('/')[-1]
            fields = doc.get('fields', {})
            
            # Extract Firestore document fields
            user_id_field = fields.get('userId', {}).get('stringValue', '')
            signature_name = fields.get('signatureName', {}).get('stringValue', '')
            email_field = fields.get('email', {}).get('stringValue', '')
            phone_field = fields.get('phone', {}).get('stringValue', '')

            firestore_map[uid] = {
                'userId': user_id_field,
                'signatureName': signature_name,
                'email': email_field,
                'phone': phone_field
            }
    print(f"Successfully retrieved {len(firestore_map)} profiles from Firestore.")
except Exception as e:
    print(f"Note: Could not query Firestore REST API ({e}). Falling back to Auth UIDs.")

input_csv = 'users_export.csv'
output_csv = 'correlated_users_files.csv'

rows = []
try:
    with open(input_csv, mode='r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            uid = row.get('uid', '').strip()
            email = row.get('email', '').strip()
            phone = row.get('phone', '').strip()
            displayName = row.get('displayName', '').strip()

            profile = firestore_map.get(uid, {})
            file_user_id = profile.get('userId', '') or uid
            name = displayName or profile.get('signatureName', '')
            user_email = email or profile.get('email', '')
            user_phone = phone or profile.get('phone', '')

            rows.append({
                'uid': uid,
                'file_user_id': file_user_id,
                'name': name,
                'email': user_email,
                'phone': user_phone,
                'uploaded_file_pattern': f"PDData_{file_user_id}_*.zip"
            })
except FileNotFoundError:
    print(f"Notice: '{input_csv}' not found. Building CSV directly from Firestore...")
    for uid, profile in firestore_map.items():
        file_user_id = profile.get('userId', '') or uid
        rows.append({
            'uid': uid,
            'file_user_id': file_user_id,
            'name': profile.get('signatureName', ''),
            'email': profile.get('email', ''),
            'phone': profile.get('phone', ''),
            'uploaded_file_pattern': f"PDData_{file_user_id}_*.zip"
        })

fieldnames = ['uid', 'file_user_id', 'name', 'email', 'phone', 'uploaded_file_pattern']
with open(output_csv, mode='w', newline='', encoding='utf-8') as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(rows)

print(f"\nSUCCESS: Generated '{output_csv}' with {len(rows)} user records.")