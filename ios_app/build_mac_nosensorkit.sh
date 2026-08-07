#!/bin/bash
# ==============================================================================
# Script: build_mac_nosensorkit.sh
# Purpose: Build PDCollectiOS without SensorKit (for TestFlight / Clean App Store signing) on Mac.
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "============================================================"
echo " 1. Configuring for Clean Signing (No SensorKit)..."
echo "============================================================"
python3 toggle_sensorkit.py testflight || python toggle_sensorkit.py testflight

if command -v xcodegen &> /dev/null; then
    echo "Regenerating Xcode project..."
    xcodegen generate
fi

echo "============================================================"
echo " 2. Building Standard TestFlight IPA..."
echo "============================================================"
SCHEME="PDCollectiOS"
PROJECT="PDCollectiOS.xcodeproj"
CONFIGURATION="Release"
BUILD_DIR="$SCRIPT_DIR/build_nosensorkit"
ARCHIVE_PATH="$BUILD_DIR/PDCollectiOS_TestFlight.xcarchive"
EXPORT_PATH="$BUILD_DIR/ipa"
EXPORT_OPTIONS_PLIST="$BUILD_DIR/ExportOptions.plist"

mkdir -p "$BUILD_DIR"
mkdir -p "$EXPORT_PATH"

echo "Cleaning SPM derived cache..."
rm -rf ~/Library/Developer/Xcode/DerivedData/PDCollectiOS-* 2>/dev/null || true
rm -rf ~/Library/Caches/org.swift.swiftpm 2>/dev/null || true

xcodebuild -resolvePackageDependencies \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -scmProvider system \
  CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES=YES

cat <<EOF > "$EXPORT_OPTIONS_PLIST"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store</string>
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
  -allowProvisioningUpdates \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS="DISABLE_SENSORKIT" \
  CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES=YES \
  COMPILER_INDEX_STORE_ENABLE=NO

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" \
  -exportPath "$EXPORT_PATH" \
  -allowProvisioningUpdates

echo "============================================================"
echo " NO-SENSORKIT BUILD SUCCESSFUL!"
echo " IPA exported to: $EXPORT_PATH/PDCollectiOS.ipa"
echo "============================================================"
