import re

# v3.7.27 (vc 113): Duplicate upload prevention, recursive iOS size display, Android upload on launch, face distance fallback
with open('app/build.gradle.kts', 'r') as f:
    data = f.read()
data = re.sub(r'versionCode = 112', r'versionCode = 113', data)
data = re.sub(r'versionName = "3.7.26"', r'versionName = "3.7.27"', data)
data = re.sub(r'v3\.7\.26 \(vc 112\)', r'v3.7.27 (vc 113)', data)
with open('app/build.gradle.kts', 'w') as f:
    f.write(data)

with open('../../ios_app/project.yml', 'r') as f:
    data = f.read()
data = re.sub(r'MARKETING_VERSION: 3\.7\.26', r'MARKETING_VERSION: 3.7.27', data)
data = re.sub(r'CURRENT_PROJECT_VERSION: 112', r'CURRENT_PROJECT_VERSION: 113', data)
with open('../../ios_app/project.yml', 'w') as f:
    f.write(data)
