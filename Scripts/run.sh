#!/bin/bash
# Build, relaunch, and tail the app's log output.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/Scripts/build_app.sh"
pkill -x LingTip 2>/dev/null || true
sleep 0.3
open "$ROOT/build/LingTip.app"
echo "LingTip launched. Look for the speech-bubble icon in the menu bar."
