#!/bin/zsh
# Installs (or updates) Sputnik from the latest GitHub release.
#
#   curl -fsSL https://raw.githubusercontent.com/Omarbng/Sputnik/main/scripts/install.sh | zsh
#
# It downloads the .dmg, copies Sputnik.app into /Applications (or ~/Applications), and opens
# it. Downloaded this way, macOS doesn't ask you to click "Open Anyway".
set -euo pipefail

REPO="Omarbng/Sputnik"

if [[ "$(uname -m)" != arm64 ]]; then
  echo "Sputnik needs a Mac with Apple silicon (M1 or later)."; exit 1
fi
if (( ${$(sw_vers -productVersion)%%.*} < 26 )); then
  echo "Sputnik needs macOS 26 or later (you have $(sw_vers -productVersion))."; exit 1
fi

echo "==> Finding the latest Sputnik"
url=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
  | grep -o '"browser_download_url": *"[^"]*\.dmg"' | head -1 | sed -E 's/.*"(https[^"]+)"$/\1/')
if [[ -z "$url" ]]; then
  echo "No release is published yet. See https://github.com/$REPO"; exit 1
fi

work=$(mktemp -d)
mount="$work/volume"
cleanup() { hdiutil detach -quiet "$mount" 2>/dev/null || true; rm -rf "$work"; }
trap cleanup EXIT

echo "==> Downloading $(basename "$url")"
curl -fL --progress-bar "$url" -o "$work/Sputnik.dmg"
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$mount" "$work/Sputnik.dmg"

dest=/Applications
[[ -w "$dest" ]] || { dest="$HOME/Applications"; mkdir -p "$dest"; }
echo "==> Installing into $dest"
pkill -x Sputnik 2>/dev/null && sleep 1 || true
rm -rf "$dest/Sputnik.app"
ditto "$mount/Sputnik.app" "$dest/Sputnik.app"
xattr -dr com.apple.quarantine "$dest/Sputnik.app" 2>/dev/null || true

open "$dest/Sputnik.app"
echo "==> Done. Sputnik is in your menu bar; the setup opens on first launch."
