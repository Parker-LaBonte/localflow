#!/bin/bash
# LocalFlow installer: downloads the latest release and puts LocalFlow.app in /Applications.
#   curl -fsSL https://raw.githubusercontent.com/Parker-LaBonte/localflow/main/install.sh | bash
set -euo pipefail

REPO="Parker-LaBonte/localflow"
URL="https://github.com/$REPO/releases/latest/download/LocalFlow.zip"

[[ "$(uname -s)" == "Darwin" ]] || { echo "LocalFlow is a macOS app."; exit 1; }
[[ "$(uname -m)" == "arm64" ]] || { echo "LocalFlow needs an Apple Silicon Mac (M1 or newer)."; exit 1; }
major=$(sw_vers -productVersion | cut -d. -f1)
(( major >= 14 )) || { echo "LocalFlow needs macOS 14 Sonoma or newer."; exit 1; }

DEST=/Applications
[[ -w "$DEST" ]] || DEST="$HOME/Applications"
mkdir -p "$DEST"

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
echo "Downloading LocalFlow..."
curl -fL --progress-bar "$URL" -o "$tmp/LocalFlow.zip"
ditto -x -k "$tmp/LocalFlow.zip" "$tmp"

pkill -x LocalFlow 2>/dev/null || true
rm -rf "$DEST/LocalFlow.app"
mv "$tmp/LocalFlow.app" "$DEST/"
xattr -dr com.apple.quarantine "$DEST/LocalFlow.app" 2>/dev/null || true

echo "Installed to $DEST/LocalFlow.app. Opening it..."
open "$DEST/LocalFlow.app"
echo "LocalFlow lives in your menu bar. Setup downloads the models (about 0.6 to 2.4 GB) and asks for two permissions."
