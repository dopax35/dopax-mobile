import json
import csv
import os
import urllib.request

# Load token from configstore
token_file = os.path.join(os.environ.get('USERPROFILE', ''), '.config', 'configstore', 'firebase-tools.json')

with open(token_file, 'r', encoding='utf-8') as f:
    config = json.load(f)

access_token = config['tokens']['access_token']

project_id = 'dopa-x-app'
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
            
            user_id = fields.get('userId', {}).get('stringValue', '')
            email = fields.get('email', {}).get('stringValue', '')
            name = fields.get('signatureName', {}).get('stringValue', '')
            phone = fields.get('phone', {}).get('stringValue', '')

            firestore_map[uid] = {
                'file_user_id': user_id,
                'email': email,
                'name': name,
                'phone': phone
            }
except Exception as e:
    print(f"Error fetching Firestore: {e}")

print(f"Retrieved {len(firestore_map)} documents from Firestore users collection.")

# Load existing users_export.csv
input_csv = 'users_export.csv'
output_csv = 'correlated_users_files.csv'

rows = []
if os.path.exists(input_csv):
    with open(input_csv, mode='r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            uid = row.get('uid', '').strip()
            email = row.get('email', '').strip()
            phone = row.get('phone', '').strip()
            displayName = row.get('displayName', '').strip()

            profile = firestore_map.get(uid, {})
            file_user_id = profile.get('file_user_id', '') or uid
            name = displayName or profile.get('name', '')
            user_email = email or profile.get('email', '')
            user_phone = phone or profile.get('phone', '')

            rows.append({
                'uid': uid,
                'file_user_id': file_user_id,
                'email': user_email,
                'phone': user_phone,
                'displayName': name,
                'uploaded_file_pattern': f"PDData_{file_user_id}_*.zip"
            })
else:
    for uid, data in firestore_map.items():
        file_user_id = data['file_user_id'] or uid
        rows.append({
            'uid': uid,
            'file_user_id': file_user_id,
            'email': data['email'],
            'phone': data['phone'],
            'displayName': data['name'],
            'uploaded_file_pattern': f"PDData_{file_user_id}_*.zip"
        })

fieldnames = ['uid', 'file_user_id', 'email', 'phone', 'displayName', 'uploaded_file_pattern']
with open(output_csv, mode='w', newline='', encoding='utf-8') as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(rows)

print(f"Successfully created '{output_csv}' with {len(rows)} correlated records!")
