#!/bin/zsh
# Build ClipDock, assemble + sign the .app, install to ~/Applications, relaunch.
# Usage: ./run.sh [debug|release]   (default: debug)
set -euo pipefail

cd "${0:A:h}"

CONFIG="${1:-debug}"
APP_NAME="ClipDock"
SIGN_IDENTITY="ClipDock Dev"          # self-signed, stable across rebuilds (see PROGRESS.md)
INSTALL_DIR="$HOME/Applications"
source ./swiftpm-env.sh
SWIFT_FLAGS=(-c "$CONFIG" "${SWIFTPM_COMMON_FLAGS[@]}")
# Test builds, for scripts only: launched with CLIPDOCK_FAKE_AUTH=1 they skip Touch ID, and
# with CLIPDOCK_TEST_TARGET_ONLY=1 they send ⌘V/⌘C only into the test target app.
# Never leave one installed: rebuild with plain ./run.sh afterwards.
if [[ "${CLIPDOCK_TEST_BUILD:-}" == 1 ]]; then
  echo "==> TEST BUILD (Touch ID can be skipped)"
  SWIFT_FLAGS+=(-Xswiftc -DCLIPDOCK_TEST_BUILD)
fi
STAGE="$BUILD_ROOT/$APP_NAME.app"

echo "==> swift build ($CONFIG)"
swift build "${SWIFT_FLAGS[@]}" --product "$APP_NAME"
BIN_DIR="$(swift build "${SWIFT_FLAGS[@]}" --show-bin-path)"

echo "==> assembling $STAGE"
rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$STAGE/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$STAGE/Contents/Info.plist"
# SwiftPM resource bundles (from dependencies) go in Contents/Resources.
for bundle in "$BIN_DIR"/*.bundle(N); do
  cp -R "$bundle" "$STAGE/Contents/Resources/"
done

echo "==> signing with \"$SIGN_IDENTITY\""
chmod -R u+w "$STAGE"   # dependency resource bundles arrive read-only
xattr -cr "$STAGE"      # codesign rejects FinderInfo / resource-fork xattrs
codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$STAGE"
codesign --verify --strict "$STAGE"

echo "==> installing to $INSTALL_DIR"
if pgrep -x "$APP_NAME" >/dev/null; then
  pkill -x "$APP_NAME" || true
  for _ in {1..50}; do pgrep -x "$APP_NAME" >/dev/null || break; sleep 0.1; done
fi
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/$APP_NAME.app"
ditto "$STAGE" "$INSTALL_DIR/$APP_NAME.app"

echo "==> launching"
open "$INSTALL_DIR/$APP_NAME.app"
