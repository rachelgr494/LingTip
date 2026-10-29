#!/bin/bash
# Builds LingTip and installs it into /Applications (or ~/Applications if that is not
# writable), replacing any previous copy, then launches it.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/Scripts/build_app.sh"

DEST="${INSTALL_DIR:-/Applications}"
if [ ! -w "$DEST" ]; then DEST="$HOME/Applications"; fi
mkdir -p "$DEST"

pkill -x LingTip 2>/dev/null || true
sleep 0.3
rm -rf "$DEST/LingTip.app"
ditto "$ROOT/build/LingTip.app" "$DEST/LingTip.app"   # ditto preserves the code signature
open "$DEST/LingTip.app"
echo "Installed and launched $DEST/LingTip.app. Look for the speech-bubble icon in the menu bar."
