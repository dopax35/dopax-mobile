import json, csv

with open('users.json', 'r', encoding='utf-8') as f:
    data = json.load(f)

with open('users_export.csv', 'w', newline='', encoding='utf-8') as csv_file:
    writer = csv.writer(csv_file)
    writer.writerow(['uid', 'email', 'phone', 'displayName'])

    for user in data.get('users', []):
        writer.writerow([
            user.get('localId', ''),
            user.get('email', ''),
            user.get('phoneNumber', ''),
            user.get('displayName', '')
        ])

print("Saved users_export.csv successfully!")