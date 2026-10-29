#!/bin/bash
# Builds LingTip with SwiftPM and assembles build/LingTip.app.
# Signing: set CODESIGN_IDENTITY to a certificate name for a stable identity
# (keeps the Accessibility grant across rebuilds); defaults to ad-hoc ("-").
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${CONFIG:-release}"
APP="$ROOT/build/LingTip.app"
IDENTITY="${CODESIGN_IDENTITY:--}"

cd "$ROOT"
# Only the app product: LingTipChecks uses @testable import and is debug-only.
swift build -c "$CONFIG" --product LingTip
BIN_DIR="$(swift build -c "$CONFIG" --product LingTip --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/LingTip" "$APP/Contents/MacOS/LingTip"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Icons generated from the logo by Scripts/make_icons.swift.
ICONS="$ROOT/Support/Icons"
cp "$ICONS/AppIcon.icns" "$ICONS/MenuBarIconTemplate.png" "$ICONS/MenuBarIconTemplate@2x.png" \
   "$ICONS/Logo.png" "$ICONS/Logo@2x.png" "$APP/Contents/Resources/"

# SwiftPM resource bundles (e.g. KeyboardShortcuts localizations) are looked up next to the executable or in Resources.
for bundle in "$BIN_DIR"/*.bundle; do
  [ -d "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done

# The explicit designated requirement keys the signature on the bundle identifier instead
# of the per-build code hash, so the Accessibility grant (TCC) survives rebuilds even with
# ad-hoc signing.
codesign --force --sign "$IDENTITY" --identifier com.lingtip.LingTip \
  --requirements '=designated => identifier "com.lingtip.LingTip"' "$APP"
echo "Built $APP (signed: $IDENTITY)"
