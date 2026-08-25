import os
import json
import csv
import urllib.request

print("==========================================================================")
print("  Dopa-X Active User Progress, Compliance & Data Integrity Audit")
print("==========================================================================")

user_profile = os.environ.get('USERPROFILE', '')
appdata = os.environ.get('APPDATA', '')

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

project_id = 'dopa-x-app'

def fetch_firestore_collection(collection_name):
    if not access_token:
        return {}
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
                        parsed_fields[key] = int(val['integerValue'])
                    elif 'mapValue' in val:
                        parsed_fields[key] = val['mapValue']
                data_map[doc_id] = parsed_fields
    except Exception as e:
        print(f"Notice: Could not fetch collection '{collection_name}': {e}")
    return data_map

users_profiles = fetch_firestore_collection("users")

master_correlations_csv = 'master_user_correlations.csv'
correlated_users = []
if os.path.exists(master_correlations_csv):
    with open(master_correlations_csv, mode='r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            correlated_users.append(row)

if not correlated_users:
    input_csv = 'users_export.csv'
    if os.path.exists(input_csv):
        with open(input_csv, mode='r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                uid = row.get('uid', '').strip()
                profile = users_profiles.get(uid, {})
                file_user_id = profile.get('userId', '') or uid
                correlated_users.append({
                    'uid': uid,
                    'file_user_id': file_user_id,
                    'email': row.get('email', ''),
                    'phone': row.get('phone', ''),
                    'name': row.get('displayName', '') or profile.get('signatureName', '') or uid,
                    'platform': profile.get('platform', 'Unknown'),
                    'uploaded_file_pattern': f"PDData_{file_user_id}_*.zip"
                })

manifest_paths = [
    os.path.join('drive', 'manifest.jsonl'),
    os.path.join('backend', '.migration-source', 'drive', 'manifest.jsonl'),
    os.path.join('.migration-source', 'drive', 'manifest.jsonl'),
]

manifest_path = None
for mp in manifest_paths:
    if os.path.exists(mp):
        manifest_path = mp
        break

drive_files_by_code = {}
if manifest_path and os.path.exists(manifest_path):
    with open(manifest_path, mode='r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                item = json.loads(line)
                name = item.get('name', '')
                bytes_size = item.get('bytes', 0)
                parts = name.split('_')
                if len(parts) >= 3 and parts[0] == 'PDData':
                    code = parts[1]
                    date_part = parts[2].replace('.zip', '').replace('_iOS', '')
                    if code not in drive_files_by_code:
                        drive_files_by_code[code] = []
                    drive_files_by_code[code].append({
                        'filename': name,
                        'bytes': bytes_size,
                        'date': date_part
                    })
            except Exception:
                pass

print(f"Loaded {len(correlated_users)} registered users.")
print(f"Found Drive uploads for {len(drive_files_by_code)} participant codes.")

results = []
TEN_MB = 10 * 1024 * 1024

for u in correlated_users:
    uid = u.get('uid', '')
    code = u.get('file_user_id', '') or uid
    email = u.get('email', '')
    name = u.get('name', '').strip() or uid
    platform = (u.get('platform', '') or 'android').lower()

    # Look up files by code or by uid
    user_files = drive_files_by_code.get(code, []) or drive_files_by_code.get(uid, [])
    
    daily_loads = {}
    for f in user_files:
        d = f['date']
        if d not in daily_loads:
            daily_loads[d] = {'total_bytes': 0, 'files': []}
        daily_loads[d]['total_bytes'] += f['bytes']
        daily_loads[d]['files'].append(f)

    total_files = len(user_files)
    total_bytes = sum(f['bytes'] for f in user_files)
    
    if 'ios' in platform or 'iphone' in platform or 'apple' in platform:
        is_compliant = total_files > 0
        compliance_reason = "File Present (iPhone)" if is_compliant else "No Files Uploaded (iPhone)"
    else:
        max_daily_bytes = max([dl['total_bytes'] for dl in daily_loads.values()], default=0)
        is_compliant = max_daily_bytes > TEN_MB
        if is_compliant:
            compliance_reason = f"Daily Load > 10MB ({round(max_daily_bytes/(1024*1024), 2)}MB)"
        elif total_files > 0:
            compliance_reason = f"File Size Under 10MB ({round(max_daily_bytes/(1024*1024), 2)}MB)"
        else:
            compliance_reason = "No Files Uploaded (Android)"

    has_sensor_data = total_files > 0
    has_activity_data = total_files > 0
    
    integrity_alerts = []
    if total_files == 0:
        integrity_alerts.append("No Data Uploaded")
    if not has_sensor_data:
        integrity_alerts.append("Missing Sensor Data")
    if not has_activity_data:
        integrity_alerts.append("Missing Activity Data")

    integrity_status = "Healthy" if total_files > 0 else "No Uploads"

    results.append({
        'uid': uid,
        'file_user_id': code,
        'name': name,
        'email': email,
        'platform': platform.upper(),
        'total_files': total_files,
        'total_bytes': total_bytes,
        'total_mb': round(total_bytes / (1024 * 1024), 2),
        'latest_date': max(daily_loads.keys(), default='None'),
        'compliance_status': 'PROPER_USAGE' if is_compliant else 'IMPROPER_USAGE',
        'compliance_reason': compliance_reason,
        'integrity_status': integrity_status,
        'integrity_alerts': "; ".join(integrity_alerts) if integrity_alerts else "None"
    })

output_csv = 'master_user_progress_review.csv'
fieldnames = ['uid', 'file_user_id', 'name', 'email', 'platform', 'total_files', 'total_bytes', 'total_mb', 'latest_date', 'compliance_status', 'compliance_reason', 'integrity_status', 'integrity_alerts']

with open(output_csv, mode='w', newline='', encoding='utf-8') as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(results)

print("--------------------------------------------------------------------------")
print(f"SUCCESS: Exported user progress & compliance report '{output_csv}' with {len(results)} records.")
print("==========================================================================")
