#!/bin/zsh
# Builds a Sputnik release to share: a release build, signed with the same self-signed
# certificate as everyday builds (so people's permissions survive updates), packed into
# dist/Sputnik-<version>.dmg with an Applications shortcut. Upload the .dmg to a GitHub release
# yourself; nothing is uploaded here.
# Usage: ./release.sh            (bump CFBundleShortVersionString in Resources/Info.plist first)
set -euo pipefail
cd "${0:A:h}"
source ./swiftpm-env.sh

APP_NAME="Sputnik"
SIGN_IDENTITY="${SIGN_IDENTITY:-ClipDock Dev}"   # the certificate's name predates the rename
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
FLAGS=(-c release "${SWIFTPM_COMMON_FLAGS[@]}")
WORK="$BUILD_ROOT/release"
STAGE="$WORK/$APP_NAME.app"
DMG="dist/$APP_NAME-$VERSION.dmg"

echo "==> swift build (release) $VERSION"
swift build "${FLAGS[@]}" --product "$APP_NAME"
BIN_DIR="$(swift build "${FLAGS[@]}" --show-bin-path)"

echo "==> assembling"
rm -rf "${WORK:?}"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$STAGE/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$STAGE/Contents/Info.plist"
for bundle in "$BIN_DIR"/*.bundle(N); do cp -R "$bundle" "$STAGE/Contents/Resources/"; done
chmod -R u+w "$STAGE"
xattr -cr "$STAGE"

echo "==> signing with \"$SIGN_IDENTITY\""
codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$STAGE"
codesign --verify --strict "$STAGE"

echo "==> making $DMG"
mkdir -p "$WORK/dmg" dist
ditto "$STAGE" "$WORK/dmg/$APP_NAME.app"
ln -s /Applications "$WORK/dmg/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname "$APP_NAME $VERSION" -srcfolder "$WORK/dmg" -format UDZO "$DMG"

echo "==> done"
ls -lh "$DMG"
shasum -a 256 "$DMG"
