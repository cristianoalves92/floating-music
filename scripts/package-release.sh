#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
./scripts/build.sh
mkdir -p dist
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)
ARCHIVE="Floating-Music-v${VERSION}-universal.zip"
STAGING=$(mktemp -d /tmp/floating-music-release.XXXXXX)
trap 'rm -rf "$STAGING"' EXIT
ditto --norsrc --noextattr 'build/Floating Music.app' "$STAGING/Floating Music.app"
xattr -cr "$STAGING/Floating Music.app"
codesign --verify --deep --strict "$STAGING/Floating Music.app"
ditto -c -k --norsrc --noextattr --keepParent "$STAGING/Floating Music.app" "dist/$ARCHIVE"
(cd dist && shasum -a 256 "$ARCHIVE" > SHA256SUMS.txt)
echo "$PWD/dist/$ARCHIVE"
