#!/bin/bash
# Builds "CST to Patch.app" from source.
#
#   ./build.sh                 build an unsigned (ad-hoc signed) app for your own Mac
#   ./build.sh --notarize      build, sign with Developer ID, notarize and staple
#
# Signing settings come from a file called signing.env next to this script
# (never committed, see signing.env.example) or from environment variables.
set -e
cd "$(dirname "$0")"

APP_NAME="CST to Patch"
APP="dist/$APP_NAME.app"
NOTARIZE=0
[ "$1" = "--notarize" ] && NOTARIZE=1
[ -f signing.env ] && source signing.env

command -v swiftc >/dev/null || { echo "swiftc not found. Install Xcode or run: xcode-select --install"; exit 1; }

rm -rf build dist
mkdir -p build "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> Making icon"
if command -v iconutil >/dev/null; then
  SET=build/AppIcon.iconset; mkdir -p "$SET"
  for s in 16 32 128 256 512; do
    sips -z $s $s Resources/AppIcon-1024.png --out "$SET/icon_${s}x${s}.png" >/dev/null
    d=$((s*2)); sips -z $d $d Resources/AppIcon-1024.png --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$SET" -o "$APP/Contents/Resources/AppIcon.icns"
else
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

echo "==> Compiling (Apple silicon + Intel)"
swiftc -parse-as-library -O -target arm64-apple-macos13  Sources/main.swift -o build/arm64
swiftc -parse-as-library -O -target x86_64-apple-macos13 Sources/main.swift -o build/x86_64
lipo -create build/arm64 build/x86_64 -output "$APP/Contents/MacOS/CSTtoPatch"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if [ "$NOTARIZE" = 0 ]; then
  echo "==> Ad-hoc signing (runs on this Mac only)"
  codesign --force --deep --sign - "$APP"
  echo; echo "Done: $(pwd)/$APP"
  exit 0
fi

: "${TEAM_ID:?Set TEAM_ID in signing.env}"
: "${APPLE_ID:?Set APPLE_ID in signing.env}"
PROFILE="${NOTARY_PROFILE:-cst-to-patch-notary}"

IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | grep "Developer ID Application" | grep "($TEAM_ID)" | head -1 | sed -E 's/.*"(.*)"/\1/')}"
[ -n "$IDENTITY" ] || { echo "No 'Developer ID Application' certificate for team $TEAM_ID in your Keychain."; exit 1; }

echo "==> Signing with: $IDENTITY"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  echo "==> Saving notary login in your Keychain (asks for your app-specific password once)"
  xcrun notarytool store-credentials "$PROFILE" --apple-id "$APPLE_ID" --team-id "$TEAM_ID"
fi

echo "==> Notarizing (takes a few minutes)"
ditto -c -k --keepParent "$APP" build/upload.zip
xcrun notarytool submit build/upload.zip --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
spctl --assess --type execute --verbose "$APP"

ditto -c -k --keepParent "$APP" "dist/$APP_NAME.zip"
echo; echo "Done: $(pwd)/$APP"
echo "Share: $(pwd)/dist/$APP_NAME.zip"
