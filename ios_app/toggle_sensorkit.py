import sys
import os
import re

print("==========================================================================")
print("  iOS SensorKit & Entitlement Switcher (TestFlight vs Research Build)")
print("==========================================================================")

script_dir = os.path.dirname(os.path.abspath(__file__))
if os.path.exists(os.path.join(script_dir, 'project.yml')):
    ios_app_dir = script_dir
else:
    ios_app_dir = os.path.join(script_dir, 'ios_app')

ios_dir = os.path.join(ios_app_dir, 'PDCollectiOS')
entitlements_path = os.path.join(ios_dir, 'PDCollectiOS.entitlements')
keyboard_entitlements_path = os.path.join(ios_dir, 'KeyboardExtension', 'KeyboardExtension.entitlements')
info_plist_path = os.path.join(ios_dir, 'Info.plist')
project_yml_path = os.path.join(ios_app_dir, 'project.yml')

if len(sys.argv) < 2:
    print("Usage:")
    print("  python toggle_sensorkit.py testflight   # Clean entitlements for TestFlight / Automatic Signing")
    print("  python toggle_sensorkit.py full         # Add SensorKit entitlement for Research build")
    sys.exit(1)

mode = sys.argv[1].lower()

def replace_last_dict_tag(content, insertion):
    idx = content.rfind('</dict>')
    if idx != -1:
        return content[:idx] + insertion + '\n' + content[idx:]
    return content

# Read files
with open(entitlements_path, 'r', encoding='utf-8') as f:
    entitlements_content = f.read()

with open(info_plist_path, 'r', encoding='utf-8') as f:
    info_plist_content = f.read()

project_yml_content = ""
if os.path.exists(project_yml_path):
    with open(project_yml_path, 'r', encoding='utf-8') as f:
        project_yml_content = f.read()

if mode == 'testflight' or mode == 'no-sensorkit' or mode == 'no-app-groups':
    print("Configuring iOS App for TestFlight / Clean Automatic Signing...")

    # 1. Clean main entitlements
    clean_entitlements = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>com.apple.developer.healthkit</key>
\t<true/>
\t<key>com.apple.developer.healthkit.access</key>
\t<array/>
</dict>
</plist>"""
    with open(entitlements_path, 'w', encoding='utf-8') as f:
        f.write(clean_entitlements)
    print(" -> Reset PDCollectiOS.entitlements to standard HealthKit only.")

    # 2. Clean keyboard extension entitlements
    if os.path.exists(keyboard_entitlements_path):
        clean_kb = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
</dict>
</plist>"""
        with open(keyboard_entitlements_path, 'w', encoding='utf-8') as f:
            f.write(clean_kb)
        print(" -> Reset KeyboardExtension.entitlements.")

    # 3. Remove NSSensorKit keys and NSSensorKitUsageDetail dict from Info.plist
    info_clean = re.sub(
        r'\s*<key>NSSensorKitUsageDescription.*?</string>',
        '',
        info_plist_content,
        flags=re.DOTALL
    )
    info_clean = re.sub(
        r'\s*<key>NSSensorKitPrivacyPolicyURL.*?</string>',
        '',
        info_clean,
        flags=re.DOTALL
    )
    info_clean = re.sub(
        r'\s*<key>NSSensorKitUsageDetail.*?</dict>\s*</dict>',
        '',
        info_clean,
        flags=re.DOTALL
    )
    with open(info_plist_path, 'w', encoding='utf-8') as f:
        f.write(info_clean)
    print(" -> Removed NSSensorKit keys from Info.plist.")

    # 4. Update project.yml
    if project_yml_content:
        project_yml_clean = re.sub(
            r'\s*com\.apple\.developer\.sensorkit\.reader\.allow:\n(\s+-[^\n]+\n?)+',
            '',
            project_yml_content
        )
        project_yml_clean = re.sub(
            r'\s*NSSensorKit[A-Za-z]+: "[^"]*"',
            '',
            project_yml_clean
        )
        if 'DISABLE_SENSORKIT' not in project_yml_clean:
            project_yml_clean = project_yml_clean.replace(
                "    settings:\n      base:\n",
                "    settings:\n      base:\n        SWIFT_ACTIVE_COMPILATION_CONDITIONS: DISABLE_SENSORKIT\n        GCC_PREPROCESSOR_DEFINITIONS: \"DISABLE_SENSORKIT=1 $(inherited)\"\n",
                1
            )
        with open(project_yml_path, 'w', encoding='utf-8') as f:
            f.write(project_yml_clean)
        print(" -> Added DISABLE_SENSORKIT flag to project.yml.")

    # 5. Direct update to project.pbxproj if xcodegen is not installed
    pbxproj_path = os.path.join(ios_app_dir, 'PDCollectiOS.xcodeproj', 'project.pbxproj')
    if os.path.exists(pbxproj_path):
        with open(pbxproj_path, 'r', encoding='utf-8') as f:
            pbx_content = f.read()
        if 'DISABLE_SENSORKIT' not in pbx_content:
            pbx_content = re.sub(
                r'(\s+SWIFT_ACTIVE_COMPILATION_CONDITIONS = )([^;\n]+);',
                r'\1"\2 DISABLE_SENSORKIT";\n\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = "DISABLE_SENSORKIT=1 $(inherited)";',
                pbx_content
            )
            with open(pbxproj_path, 'w', encoding='utf-8') as f:
                f.write(pbx_content)
            print(" -> Updated project.pbxproj with DISABLE_SENSORKIT.")

    print("\nSUCCESS: iOS project is now configured for clean automatic signing!")

elif mode == 'full' or mode == 'with-sensorkit':
    print("Restoring iOS App for Full Research Build (With SensorKit)...")

    # 1. Restore SensorKit entitlement in .entitlements
    if 'com.apple.developer.sensorkit.reader.allow' not in entitlements_content:
        sensorkit_entitlement = """\t<key>com.apple.developer.sensorkit.reader.allow</key>
\t<array>
\t\t<string>accelerometer</string>
\t\t<string>rotation-rate</string>
\t\t<string>keyboard-metrics</string>
\t\t<string>device-usage</string>
\t</array>"""
        entitlements_content = replace_last_dict_tag(entitlements_content, sensorkit_entitlement)
        with open(entitlements_path, 'w', encoding='utf-8') as f:
            f.write(entitlements_content)
    print(" -> Restored SensorKit entitlement in PDCollectiOS.entitlements.")

    # 2. Restore Info.plist keys
    if 'NSSensorKitUsageDescription' not in info_plist_content:
        sensorkit_plist_keys = """\t<key>NSSensorKitUsageDescription</key>
\t<string>PDCollect accesses SensorKit data streams to generate digital markers for Parkinson's Disease research.</string>
\t<key>NSSensorKitPrivacyPolicyURL</key>
\t<string>https://pdcollect.web.app/privacy.html</string>
\t<key>NSSensorKitUsageDetail</key>
\t<dict>
\t\t<key>SRSensorUsageAccelerometer</key>
\t\t<dict>
\t\t\t<key>Description</key>
\t\t\t<string>Used to record passive high-resolution accelerometer data for Parkinson's Disease motion analysis.</string>
\t\t</dict>
\t\t<key>SRSensorUsageRotationRate</key>
\t\t<dict>
\t\t\t<key>Description</key>
\t\t\t<string>Used to record passive gyroscope rotation rate data for Parkinson's Disease tremor and movement analysis.</string>
\t\t</dict>
\t\t<key>SRSensorUsageKeyboardMetrics</key>
\t\t<dict>
\t\t\t<key>Description</key>
\t\t\t<string>Used to collect typing cadence and error metrics to evaluate motor and cognitive function in Parkinson's Disease.</string>
\t\t</dict>
\t\t<key>SRSensorUsageDeviceUsage</key>
\t\t<dict>
\t\t\t<key>Description</key>
\t\t\t<string>Used to monitor daily smartphone usage patterns and digital activity markers related to Parkinson's Disease.</string>
\t\t</dict>
\t</dict>"""
        info_plist_content = replace_last_dict_tag(info_plist_content, sensorkit_plist_keys)
        with open(info_plist_path, 'w', encoding='utf-8') as f:
            f.write(info_plist_content)
    print(" -> Restored SensorKit keys in Info.plist.")

    # 3. Clean project.yml DISABLE_SENSORKIT if present
    if project_yml_content and 'DISABLE_SENSORKIT' in project_yml_content:
        project_yml_clean = project_yml_content.replace(
            "        SWIFT_ACTIVE_COMPILATION_CONDITIONS: DISABLE_SENSORKIT\n",
            ""
        )
        with open(project_yml_path, 'w', encoding='utf-8') as f:
            f.write(project_yml_clean)
        print(" -> Removed DISABLE_SENSORKIT flag from project.yml.")

    # 4. Remove DISABLE_SENSORKIT from project.pbxproj
    pbxproj_path = os.path.join(ios_app_dir, 'PDCollectiOS.xcodeproj', 'project.pbxproj')
    if os.path.exists(pbxproj_path):
        with open(pbxproj_path, 'r', encoding='utf-8') as f:
            pbx_content = f.read()
        if 'DISABLE_SENSORKIT' in pbx_content:
            pbx_content = re.sub(r'\s*SWIFT_ACTIVE_COMPILATION_CONDITIONS = [^;\n]*DISABLE_SENSORKIT[^;\n]*;', '', pbx_content)
            with open(pbxproj_path, 'w', encoding='utf-8') as f:
                f.write(pbx_content)
            print(" -> Removed DISABLE_SENSORKIT flag from project.pbxproj.")

    print("\nSUCCESS: iOS project is now restored to FULL SENSORKIT mode!")
