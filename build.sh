#!/bin/bash
# Builds a universal (Apple Silicon + Intel) YunziiControl.app and a shareable zip in build/.
set -euo pipefail
cd "$(dirname "$0")"
APP=build/YunziiControl.app
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
for arch in arm64 x86_64; do
  swiftc -O -parse-as-library -swift-version 5 -target "$arch-apple-macos13.0" -o "build/YunziiControl-$arch" Sources/*.swift
done
lipo -create build/YunziiControl-arm64 build/YunziiControl-x86_64 -output "$APP/Contents/MacOS/YunziiControl"
cp Info.plist "$APP/Contents/Info.plist"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
rm build/YunziiControl-arm64 build/YunziiControl-x86_64
# Sign with the local certificate when present so macOS keeps permissions across rebuilds; otherwise ad-hoc.
IDENTITY="YunziiControl Local Signing"
if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
  codesign --force --sign "$IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"
fi
echo "Built $APP"
