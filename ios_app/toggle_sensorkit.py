import sys
import os
import re

print("==========================================================================")
print("  iOS SensorKit Mode Switcher (TestFlight vs Full Research Build)")
print("==========================================================================")

script_dir = os.path.dirname(os.path.abspath(__file__))
if os.path.exists(os.path.join(script_dir, 'project.yml')):
    ios_app_dir = script_dir
else:
    ios_app_dir = os.path.join(script_dir, 'ios_app')

ios_dir = os.path.join(ios_app_dir, 'PDCollectiOS')
entitlements_path = os.path.join(ios_dir, 'PDCollectiOS.entitlements')
info_plist_path = os.path.join(ios_dir, 'Info.plist')
project_yml_path = os.path.join(ios_app_dir, 'project.yml')

if len(sys.argv) < 2:
    print("Usage:")
    print("  python toggle_sensorkit.py testflight   # Strip SensorKit for TestFlight submission")
    print("  python toggle_sensorkit.py full         # Restore SensorKit for Ad-Hoc / Research build")
    sys.exit(1)

mode = sys.argv[1].lower()

# Read entitlements
with open(entitlements_path, 'r', encoding='utf-8') as f:
    entitlements_content = f.read()

# Read Info.plist
with open(info_plist_path, 'r', encoding='utf-8') as f:
    info_plist_content = f.read()

# Read project.yml
project_yml_content = ""
if os.path.exists(project_yml_path):
    with open(project_yml_path, 'r', encoding='utf-8') as f:
        project_yml_content = f.read()

if mode == 'testflight' or mode == 'no-sensorkit':
    print("Configuring iOS App for TestFlight Submission (No SensorKit)...")

    # 1. Remove SensorKit entitlement from .entitlements
    entitlements_clean = re.sub(
        r'\s*<key>com\.apple\.developer\.sensorkit\.reader\.allow</key>\s*<array>.*?</array>',
        '',
        entitlements_content,
        flags=re.DOTALL
    )
    with open(entitlements_path, 'w', encoding='utf-8') as f:
        f.write(entitlements_clean)
    print(" -> Removed 'com.apple.developer.sensorkit.reader.allow' from PDCollectiOS.entitlements.")

    # 2. Remove NSSensorKitUsageDescription keys from Info.plist
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
    with open(info_plist_path, 'w', encoding='utf-8') as f:
        f.write(info_clean)
    print(" -> Removed NSSensorKitUsageDescription keys from Info.plist.")

    # 3. Remove SensorKit from project.yml and add DISABLE_SENSORKIT condition
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
            project_yml_clean = re.sub(
                r'(settings:\n\s+base:\n)',
                r'\1        SWIFT_ACTIVE_COMPILATION_CONDITIONS: DISABLE_SENSORKIT\n',
                project_yml_clean
            )
        with open(project_yml_path, 'w', encoding='utf-8') as f:
            f.write(project_yml_clean)
        print(" -> Removed SensorKit entitlement and added DISABLE_SENSORKIT to project.yml.")

    print("\nSUCCESS: iOS project is now configured for TESTFLIGHT distribution!")

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
        entitlements_content = entitlements_content.replace('</dict>', f'{sensorkit_entitlement}\n</dict>')
        with open(entitlements_path, 'w', encoding='utf-8') as f:
            f.write(entitlements_content)
    print(" -> Restored SensorKit entitlement in PDCollectiOS.entitlements.")

    # 2. Restore Info.plist keys
    if 'NSSensorKitUsageDescription' not in info_plist_content:
        sensorkit_plist_keys = """\t<key>NSSensorKitUsageDescription</key>
\t<string>PDCollect accesses SensorKit data streams to generate digital markers for Parkinson's Disease research.</string>
\t<key>NSSensorKitPrivacyPolicyURL</key>
\t<string>https://pdcollect.web.app/privacy.html</string>
\t<key>NSSensorKitUsageDescriptionAccelerometer</key>
\t<string>Used to record passive high-resolution accelerometer data for Parkinson's Disease motion analysis.</string>
\t<key>NSSensorKitUsageDescriptionRotationRate</key>
\t<string>Used to record passive gyroscope rotation rate data for Parkinson's Disease tremor and movement analysis.</string>
\t<key>NSSensorKitUsageDescriptionKeyboardMetrics</key>
\t<string>Used to collect typing cadence and error metrics to evaluate motor and cognitive function in Parkinson's Disease.</string>
\t<key>NSSensorKitUsageDescriptionDeviceUsage</key>
\t<string>Used to monitor daily smartphone usage patterns and digital activity markers related to Parkinson's Disease.</string>"""
        info_plist_content = info_plist_content.replace('</dict>', f'{sensorkit_plist_keys}\n</dict>')
        with open(info_plist_path, 'w', encoding='utf-8') as f:
            f.write(info_plist_content)
    print(" -> Restored SensorKit keys in Info.plist.")

    # 3. Restore project.yml
    if project_yml_content:
        project_yml_content = re.sub(
            r'\s*SWIFT_ACTIVE_COMPILATION_CONDITIONS:\s*DISABLE_SENSORKIT\n?',
            '',
            project_yml_content
        )
        if 'com.apple.developer.sensorkit.reader.allow' not in project_yml_content:
            sensorkit_yml = """        com.apple.developer.sensorkit.reader.allow:
          - accelerometer
          - rotation-rate
          - keyboard-metrics
          - device-usage"""
            project_yml_content = re.sub(
                r'(group\.com\.oriw\.pdcollect\.ios1\.shared\n)',
                r'\1' + sensorkit_yml + '\n',
                project_yml_content
            )
        with open(project_yml_path, 'w', encoding='utf-8') as f:
            f.write(project_yml_content)
        print(" -> Restored SensorKit entitlement in project.yml.")

    print("\nSUCCESS: iOS project is now restored to FULL SENSORKIT mode!")
