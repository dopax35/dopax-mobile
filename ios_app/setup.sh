#!/bin/bash
# Run this script on your Mac to generate the Xcode project.
# Prerequisites: Homebrew installed (https://brew.sh)

set -e
cd "$(dirname "$0")"

if ! command -v xcodegen &> /dev/null; then
  echo "Installing XcodeGen..."
  brew install xcodegen
fi

echo "Generating Xcode project..."
xcodegen generate

echo ""
echo "Done! Open PDCollectiOS.xcodeproj in Xcode."
echo ""
echo "Next steps:"
echo "  1. Open PDCollectiOS.xcodeproj"
echo "  2. Select your Development Team in Signing & Capabilities"
echo "  3. Connect your iPhone and run, or archive for TestFlight"
