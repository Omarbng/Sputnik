#!/bin/zsh
# Build Sputnik (formerly ClipDock), assemble + sign the .app, install to ~/Applications, relaunch.
# Usage: scripts/run.sh [debug|release]   (default: debug)
set -euo pipefail

cd "${0:A:h}/.."  # the project folder

CONFIG="${1:-debug}"
APP_NAME="Sputnik"
SIGN_IDENTITY="${SIGN_IDENTITY:-ClipDock Dev}"  # self-signed, stable across rebuilds (see PROGRESS.md)
if ! security find-identity -p codesigning | grep -q "\"$SIGN_IDENTITY\""; then
  echo "==> no \"$SIGN_IDENTITY\" certificate: signing ad hoc (permissions reset after each build)"
  SIGN_IDENTITY="-"
fi
INSTALL_DIR="$HOME/Applications"
source scripts/swiftpm-env.sh
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
for running in "$APP_NAME" ClipDock; do  # ClipDock: the app's name before 2026-11-20
  if pgrep -x "$running" >/dev/null; then
    pkill -x "$running" || true
    for _ in {1..50}; do pgrep -x "$running" >/dev/null || break; sleep 0.1; done
  fi
done
mkdir -p "$INSTALL_DIR"
rm -rf "${INSTALL_DIR:?}/$APP_NAME.app" "${INSTALL_DIR:?}/ClipDock.app"
ditto "$STAGE" "$INSTALL_DIR/$APP_NAME.app"

echo "==> launching"
open "$INSTALL_DIR/$APP_NAME.app"
