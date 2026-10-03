#!/bin/bash
# Installs the latest Vhostty release into /Applications:
#   curl -fsSL https://raw.githubusercontent.com/SunRunAway/vhostty/master/scripts/install.sh | bash
#
# The app isn't notarized. A download made with curl doesn't get the quarantine
# flag that makes Gatekeeper block it (browser downloads do).
set -euo pipefail

URL="https://github.com/SunRunAway/vhostty/releases/latest/download/Vhostty.zip"
DEST="/Applications/Vhostty.app"

if [ "$(uname -m)" != "arm64" ]; then
  echo "Vhostty releases are built for Apple Silicon only." >&2
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading $URL"
curl -fL --progress-bar "$URL" -o "$TMP/Vhostty.zip"
ditto -x -k "$TMP/Vhostty.zip" "$TMP"
xattr -dr com.apple.quarantine "$TMP/Vhostty.app" 2>/dev/null || true

if pgrep -xq Vhostty; then
  echo "Note: Vhostty is running. Quit and reopen it to use the new version."
fi
rm -rf "$DEST"
mv "$TMP/Vhostty.app" "$DEST"
echo "Installed $DEST"
