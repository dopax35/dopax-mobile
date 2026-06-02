import re
with open('app/build.gradle.kts', 'r') as f:
    data = f.read()
data = re.sub(r'versionCode = 90', r'versionCode = 91', data)
data = re.sub(r'versionName = "3.7.4"', r'versionName = "3.7.5"', data)
data = re.sub(r'v3.7.4 \(vc 90\)', r'v3.7.5 (vc 91)', data)
with open('app/build.gradle.kts', 'w') as f:
    f.write(data)
with open('../../ios_app/project.yml', 'r') as f:
    data = f.read()
data = re.sub(r'MARKETING_VERSION: 3.7.4', r'MARKETING_VERSION: 3.7.5', data)
data = re.sub(r'CURRENT_PROJECT_VERSION: 90', r'CURRENT_PROJECT_VERSION: 91', data)
with open('../../ios_app/project.yml', 'w') as f:
    f.write(data)
