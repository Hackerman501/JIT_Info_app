#!/usr/bin/env bash
# Builds an UNSIGNED .ipa for sideloading (AltStore / Sideloadly / etc.).
# Requires macOS with Xcode + XcodeGen (installed automatically via Homebrew).
set -euo pipefail
cd "$(dirname "$0")"

SCHEME="JITInfo"
CONFIG="Release"
BUILD_DIR=".build"
OUTPUT="JITInfo.ipa"

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "==> xcodegen not found, installing via Homebrew..."
    brew install xcodegen
fi

echo "==> Generating Xcode project"
xcodegen generate

echo "==> Building unsigned app (iphoneos)"
xcodebuild \
    -project JITInfo.xcodeproj \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -sdk iphoneos \
    -derivedDataPath "$BUILD_DIR" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    build

APP="$BUILD_DIR/Build/Products/$CONFIG-iphoneos/JITInfo.app"
if [ ! -d "$APP" ]; then
    echo "ERROR: built app not found at $APP" >&2
    exit 1
fi

echo "==> Packaging unsigned IPA"
rm -rf Payload "$OUTPUT"
mkdir -p Payload
cp -R "$APP" Payload/
zip -qry "$OUTPUT" Payload
rm -rf Payload

echo "==> Done: $(pwd)/$OUTPUT"
ls -lh "$OUTPUT"
