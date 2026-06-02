import requests
import json

url = "https://script.google.com/macros/s/AKfycbxwRiXDXhUmKER4wdplH2lwtEeLXDlKfP0AZQaU2fqzcmgwjD7NHAr_RkDHdUsTgudXQw/exec"
payload = {
    "action": "getUploadUrl",
    "filename": "test.zip",
    "folderId": "1QLsYUTmXIha7rn7wNIJDXVTtrcWoXdly"
}

print("Sending POST request to Apps Script...")
response = requests.post(url, json=payload, allow_redirects=True)

print("Status Code:", response.status_code)
print("Response Body:", response.text)
