#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
APP="$PWD/build/Floating Music.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
./scripts/build-icon.sh
cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
for arch in arm64 x86_64; do
    swiftc -swift-version 5 -O -target "${arch}-apple-macosx13.0" -framework AppKit -framework SwiftUI Sources/FloatingMusic.swift -o "build/FloatingMusic-${arch}"
done
lipo -create build/FloatingMusic-arm64 build/FloatingMusic-x86_64 -output "$APP/Contents/MacOS/FloatingMusic"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
cp Info.plist "$APP/Contents/Info.plist"
xattr -cr "$APP"
codesign --force --sign - "$APP"
echo "$APP"
