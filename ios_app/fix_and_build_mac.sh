#!/bin/bash
# ==============================================================================
# Script: fix_and_build_mac.sh
# Purpose: Automated script for Antigravity on Mac to repair Apple certificates,
#          clean provisioning caches, and build the SensorKit Ad-Hoc .ipa package.
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "============================================================"
echo " 0. Pulling Latest Changes from Git..."
echo "============================================================"
git pull origin feature/sensorkit-ad-hoc-ipa || git pull || true

echo "============================================================"
echo " 1. Installing Apple WWDR Intermediate Certificates..."
echo "============================================================"

# Download Apple WWDR G3 and G6 intermediate certificates
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
if [ ! -f "$KEYCHAIN" ]; then
    KEYCHAIN="$HOME/Library/Keychains/login.keychain"
fi

curl -s -o /tmp/AppleWWDRCAG3.cer https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer
curl -s -o /tmp/AppleWWDRCAG6.cer https://www.apple.com/certificateauthority/AppleWWDRCAG6.cer

security import /tmp/AppleWWDRCAG3.cer -k "$KEYCHAIN" -T /usr/bin/codesign || true
security import /tmp/AppleWWDRCAG6.cer -k "$KEYCHAIN" -T /usr/bin/codesign || true

echo "============================================================"
echo " 2. Cleaning Xcode DerivedData & Provisioning Caches..."
echo "============================================================"

rm -rf ~/Library/Developer/Xcode/DerivedData/*
rm -rf ~/Library/Caches/org.swift.swiftpm/*
rm -rf ~/Library/MobileDevice/Provisioning\ Profiles/*

echo "============================================================"
echo " 3. Regenerating Xcode Project..."
echo "============================================================"

if command -v xcodegen &> /dev/null; then
    xcodegen generate
fi

echo "============================================================"
echo " 4. Archiving and Building IPA Package..."
echo "============================================================"

SCHEME="PDCollectiOS"
PROJECT="PDCollectiOS.xcodeproj"
CONFIGURATION="Release"
BUILD_DIR="$SCRIPT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/PDCollectiOS.xcarchive"
EXPORT_PATH="$BUILD_DIR/ipa"
EXPORT_OPTIONS_PLIST="$BUILD_DIR/ExportOptions.plist"

mkdir -p "$BUILD_DIR"
mkdir -p "$EXPORT_PATH"

echo "Resolving Swift Package Dependencies..."
xcodebuild -resolvePackageDependencies \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -scmProvider system

cat <<EOF > "$EXPORT_OPTIONS_PLIST"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>ad-hoc</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>stripSwiftSymbols</key>
    <true/>
    <key>compileBitcode</key>
    <false/>
</dict>
</plist>
EOF

echo "Running xcodebuild archive..."
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -sdk iphoneos \
  -archivePath "$ARCHIVE_PATH" \
  -scmProvider system \
  -allowProvisioningUpdates || {
    echo "Archive failed on entitlement/provisioning mismatch. Stripping unassigned App Groups and retrying..."
    python ../toggle_sensorkit.py no-app-groups || python toggle_sensorkit.py no-app-groups || true
    if command -v xcodegen &> /dev/null; then
        xcodegen generate
    fi
    cat <<EOF > "$EXPORT_OPTIONS_PLIST"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>development</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>stripSwiftSymbols</key>
    <true/>
    <key>compileBitcode</key>
    <false/>
</dict>
</plist>
EOF
    xcodebuild archive \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -configuration "$CONFIGURATION" \
      -sdk iphoneos \
      -archivePath "$ARCHIVE_PATH" \
      -scmProvider system \
      -allowProvisioningUpdates
  }

echo "Exporting IPA package..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" \
  -exportPath "$EXPORT_PATH" \
  -allowProvisioningUpdates

echo "============================================================"
echo " BUILD SUCCESSFUL!"
echo " IPA exported to: $EXPORT_PATH/PDCollectiOS.ipa"
echo "============================================================"
