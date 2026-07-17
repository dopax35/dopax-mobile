import re

# v3.7.28 (vc 114): Release prep — expert review verified, changelogs backfilled.
with open('app/build.gradle.kts', 'r') as f:
    data = f.read()
data = re.sub(r'versionCode = 113', r'versionCode = 114', data)
data = re.sub(r'versionName = "3\.7\.27"', r'versionName = "3.7.28"', data)
data = re.sub(r'v3\.7\.27 \(vc 113\)', r'v3.7.28 (vc 114)', data)
with open('app/build.gradle.kts', 'w') as f:
    f.write(data)

with open('../../ios_app/project.yml', 'r') as f:
    data = f.read()
data = re.sub(r'MARKETING_VERSION: 3\.7\.27', r'MARKETING_VERSION: 3.7.28', data)
data = re.sub(r'CURRENT_PROJECT_VERSION: 113', r'CURRENT_PROJECT_VERSION: 114', data)
with open('../../ios_app/project.yml', 'w') as f:
    f.write(data)
