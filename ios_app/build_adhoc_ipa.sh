#!/bin/bash
# ==============================================================================
# Script: build_adhoc_ipa.sh
# Purpose: Compiles PDCollectiOS and exports an Ad-Hoc / Development signed .ipa
#          package containing SensorKit reader access for study devices.
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

SCHEME="PDCollectiOS"
PROJECT="PDCollectiOS.xcodeproj"
CONFIGURATION="Release"
ARCHIVE_PATH="$SCRIPT_DIR/build/PDCollectiOS.xcarchive"
EXPORT_PATH="$SCRIPT_DIR/build/ipa"
EXPORT_OPTIONS_PLIST="$SCRIPT_DIR/build/ExportOptions.plist"

echo "============================================================"
echo " Starting Ad-Hoc IPA Packaging for SensorKit Enabled Build"
echo "============================================================"

# 1. Regenerate Xcode project if xcodegen is installed
if command -v xcodegen &> /dev/null; then
  echo "Regenerating Xcode project from project.yml..."
  xcodegen generate
fi

mkdir -p "$SCRIPT_DIR/build"

# 2. Create ExportOptions.plist for Ad-Hoc distribution
echo "Creating ExportOptions.plist..."
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

# 3. Clean and Archive
echo "Archiving $SCHEME..."
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -sdk iphoneos \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates

# 4. Export IPA Package
echo "Exporting Ad-Hoc IPA package to $EXPORT_PATH..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" \
  -exportPath "$EXPORT_PATH" \
  -allowProvisioningUpdates

echo "============================================================"
echo " Build Complete!"
echo " Exported IPA location: $EXPORT_PATH/PDCollectiOS.ipa"
echo "============================================================"
