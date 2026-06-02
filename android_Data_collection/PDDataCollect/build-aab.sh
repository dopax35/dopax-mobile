#!/usr/bin/env bash
# =============================================================================
# DopaX (com.pdcollect.app) - Android App Bundle build script for macOS / Linux.
# Run from this directory:   ./build-aab.sh
#
# See build-aab.ps1 for the Windows equivalent and prereq notes.
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")"

if [ ! -f ./app/build.gradle.kts ]; then
    echo "ERROR: run this from the PDDataCollect/ directory." >&2
    exit 1
fi

if [ ! -f ./local.properties ]; then
    echo "ERROR: local.properties missing - point sdk.dir at your Android SDK." >&2
    exit 1
fi

if [ ! -f ./app/keystore.properties ]; then
    echo "ERROR: app/keystore.properties missing - add local-only release signing credentials." >&2
    exit 1
fi

echo "==> Cleaning..."
./gradlew clean

echo "==> Lint (release variant)..."
./gradlew :app:lintRelease

echo "==> Unit tests..."
./gradlew :app:testReleaseUnitTest

echo "==> Bundling release AAB..."
./gradlew :app:bundleRelease --stacktrace

aab=./app/build/outputs/bundle/release/app-release.aab
mapping=./app/build/outputs/mapping/release/mapping.txt

if [ -f "$aab" ]; then
    size=$(du -h "$aab" | cut -f1)
    echo
    echo "================================================================"
    echo "  AAB built successfully"
    echo "  Path:    $aab"
    echo "  Size:    $size"
    if [ -f "$mapping" ]; then
        echo "  Mapping: $mapping"
        echo "  (Upload mapping.txt to Play Console alongside the AAB"
        echo "   so crash stack traces are de-obfuscated automatically.)"
    fi
    echo "================================================================"
else
    echo "ERROR: build did not produce an AAB." >&2
    exit 1
fi
