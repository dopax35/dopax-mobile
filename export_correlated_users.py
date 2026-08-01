import os
import json
import csv
import urllib.request

print("==========================================================================")
print("  Dopa-X Master User & File Correlation Exporter")
print("  Correlates Server Upload File IDs (userId) <-> Emails <-> Names <-> Auth UIDs")
print("==========================================================================")

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

def fetch_firestore_collection(collection_name):
    url = f"https://firestore.googleapis.com/v1/projects/{project_id}/databases/(default)/documents/{collection_name}?pageSize=500"
    req = urllib.request.Request(url, headers={'Authorization': f'Bearer {access_token}'})
    data_map = {}
    try:
        with urllib.request.urlopen(req) as response:
            res_data = json.loads(response.read().decode('utf-8'))
            documents = res_data.get('documents', [])
            for doc in documents:
                doc_name = doc.get('name', '')
                doc_id = doc_name.split('/')[-1]
                fields = doc.get('fields', {})
                
                parsed_fields = {}
                for key, val in fields.items():
                    if 'stringValue' in val:
                        parsed_fields[key] = val['stringValue']
                    elif 'integerValue' in val:
                        parsed_fields[key] = val['integerValue']
                data_map[doc_id] = parsed_fields
    except Exception as e:
        print(f"Warning fetching collection '{collection_name}': {e}")
    return data_map

print("Fetching 'user_mappings' reverse index from Firestore...")
user_mappings = fetch_firestore_collection("user_mappings")
print(f"-> Found {len(user_mappings)} reverse lookup mapping documents.")

print("Fetching 'users' profile collection from Firestore...")
users_profiles = fetch_firestore_collection("users")
print(f"-> Found {len(users_profiles)} profile documents.")

# Read existing users_export.csv if available
auth_users = []
input_csv = 'users_export.csv'
if os.path.exists(input_csv):
    with open(input_csv, mode='r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            auth_users.append(row)
    print(f"Loaded {len(auth_users)} accounts from '{input_csv}'.")

# Build unified correlation records
all_records = []
processed_uids = set()

# Process Auth users first
for user in auth_users:
    uid = user.get('uid', '').strip()
    processed_uids.add(uid)

    email = user.get('email', '').strip()
    phone = user.get('phone', '').strip()
    name = user.get('displayName', '').strip()

    profile = users_profiles.get(uid, {})
    file_user_id = profile.get('userId', '')

    # Check user_mappings index if file_user_id was not in profile
    if not file_user_id:
        for mapping_id, mdata in user_mappings.items():
            if mdata.get('authUid') == uid:
                file_user_id = mapping_id
                break

    actual_file_id = file_user_id if file_user_id else uid
    signature_name = name or profile.get('signatureName', '')
    user_email = email or profile.get('email', '')
    user_phone = phone or profile.get('phone', '')

    all_records.append({
        'uid': uid,
        'file_user_id': actual_file_id,
        'email': user_email,
        'phone': user_phone,
        'name': signature_name,
        'platform': profile.get('platform', 'Unknown'),
        'uploaded_file_pattern': f"PDData_{actual_file_id}_*.zip"
    })

# Add any additional user_mappings entries not matched to auth_users list
for mapping_id, mdata in user_mappings.items():
    auth_uid = mdata.get('authUid', '')
    if auth_uid not in processed_uids:
        all_records.append({
            'uid': auth_uid,
            'file_user_id': mapping_id,
            'email': mdata.get('email', ''),
            'phone': mdata.get('phone', ''),
            'name': mdata.get('signatureName', ''),
            'platform': mdata.get('platform', 'Unknown'),
            'uploaded_file_pattern': f"PDData_{mapping_id}_*.zip"
        })

output_csv = 'master_user_correlations.csv'
fieldnames = ['uid', 'file_user_id', 'email', 'phone', 'name', 'platform', 'uploaded_file_pattern']

with open(output_csv, mode='w', newline='', encoding='utf-8') as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(all_records)

print("--------------------------------------------------------------------------")
print(f"SUCCESS: Exported {len(all_records)} correlated user records to '{output_csv}'.")
print("==========================================================================")
