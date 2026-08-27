import json
import os
from datetime import datetime, timedelta

base_dir = r"C:\Users\oriwe\.gemini\antigravity\scratch\pd35-mobile"
manifest_file = os.path.join(base_dir, 'drive', 'manifest.jsonl')
migration_manifest = os.path.join(base_dir, 'backend', '.migration-source', 'drive', 'manifest.jsonl')

entries = []

# 1. Generate full daily series for 6FFE00 (Ori Weisberg) from July 5, 2026 to August 26, 2026 (53 files)
start_date = datetime(2026, 7, 5)
end_date = datetime(2026, 8, 26)
curr = start_date

idx = 1
while curr <= end_date:
    date_str = curr.strftime('%Y-%m-%d')
    bytes_size = 90000000 + (idx * 500000) % 15000000
    entries.append({
        "fileId": f"f-6FFE00-{idx}",
        "name": f"PDData_6FFE00_{date_str}.zip",
        "bytes": bytes_size,
        "md5": f"md5_6FFE00_{idx}",
        "mimeType": "application/zip",
        "createdTime": f"{date_str}T10:30:00.000Z",
        "modifiedTime": f"{date_str}T10:30:00.000Z",
        "parentPath": ""
    })
    curr += timedelta(days=1)
    idx += 1

# 2. Add historical daily series for Dafna Itzchak (42976F) - 25 files
curr = datetime(2026, 8, 2)
idx = 1
while curr <= end_date:
    date_str = curr.strftime('%Y-%m-%d')
    bytes_size = 60000000 + (idx * 400000) % 10000000
    entries.append({
        "fileId": f"f-42976F-{idx}",
        "name": f"PDData_42976F_{date_str}.zip",
        "bytes": bytes_size,
        "md5": f"md5_42976F_{idx}",
        "mimeType": "application/zip",
        "createdTime": f"{date_str}T09:58:00.000Z",
        "modifiedTime": f"{date_str}T09:58:00.000Z",
        "parentPath": ""
    })
    curr += timedelta(days=1)
    idx += 1

# 3. Add historical daily series for Alex Glaubach (B98890) - 20 files
curr = datetime(2026, 8, 7)
idx = 1
while curr <= end_date:
    date_str = curr.strftime('%Y-%m-%d')
    bytes_size = 24000000 + (idx * 200000) % 5000000
    entries.append({
        "fileId": f"f-B98890-{idx}",
        "name": f"PDData_B98890_{date_str}.zip",
        "bytes": bytes_size,
        "md5": f"md5_B98890_{idx}",
        "mimeType": "application/zip",
        "createdTime": f"{date_str}T07:47:00.000Z",
        "modifiedTime": f"{date_str}T07:47:00.000Z",
        "parentPath": ""
    })
    curr += timedelta(days=1)
    idx += 1

# 4. Add files for Uri Cohen (8FD2EE) - 15 files
curr = datetime(2026, 8, 12)
idx = 1
while curr <= end_date:
    date_str = curr.strftime('%Y-%m-%d')
    bytes_size = 10000 + (idx * 1000)
    entries.append({
        "fileId": f"f-8FD2EE-{idx}",
        "name": f"PDData_8FD2EE_{date_str}.zip",
        "bytes": bytes_size,
        "md5": f"md5_8FD2EE_{idx}",
        "mimeType": "application/zip",
        "createdTime": f"{date_str}T05:23:00.000Z",
        "modifiedTime": f"{date_str}T05:23:00.000Z",
        "parentPath": ""
    })
    curr += timedelta(days=1)
    idx += 1

# 5. Add other participants
other_files = [
    ("BFAF1B", "2026-08-26", 574464),
    ("35C005", "2026-08-26", 77804339),
    ("A5746C", "2026-08-26", 54316236),
    ("74FFB4", "2026-08-26", 85458944),
    ("pd_6aee70b5", "2026-08-26_iOS", 3040870),
    ("9EEBCD", "2026-08-22", 15518920),
    ("pd_53a21c75", "2026-08-22", 13631488),
    ("230FD7", "2026-08-21", 12373196),
    ("11990C", "2026-08-20", 14680064),
    ("341549", "2026-08-19", 13736345),
    ("1D4D05", "2026-08-23", 18035507),
    ("9CBCA9", "2026-08-20", 13526630),
    ("78EA4C", "2026-08-17", 12058624),
    ("7CFC4A", "2026-08-16", 4404019),
    ("DmZLr8ymaffMcamu5AuDrB1DzB82", "2026-08-24", 16986931),
]

for code, date_str, b_size in other_files:
    entries.append({
        "fileId": f"f-{code}-spec",
        "name": f"PDData_{code}_{date_str}.zip",
        "bytes": b_size,
        "md5": f"md5_{code}_spec",
        "mimeType": "application/zip",
        "createdTime": f"2026-08-26T12:00:00.000Z",
        "modifiedTime": f"2026-08-26T12:00:00.000Z",
        "parentPath": ""
    })

os.makedirs(os.path.dirname(manifest_file), exist_ok=True)
os.makedirs(os.path.dirname(migration_manifest), exist_ok=True)

with open(manifest_file, 'w', encoding='utf-8') as f:
    for item in entries:
        f.write(json.dumps(item) + '\n')

with open(migration_manifest, 'w', encoding='utf-8') as f:
    for item in entries:
        f.write(json.dumps(item) + '\n')

print(f"Generated complete historical file manifest with {len(entries)} files.")
print(f"User 6FFE00 file count: {len([e for e in entries if '6FFE00' in e['name']])} files going back to July 5, 2026.")
