#!/bin/bash
# Package the SwiftPM executable into a double-clickable Hexlens.app (no terminal needed to run).
# Bundles the SPM resource bundles (required for the augment data) next to the binary AND in
# Resources so Bundle.module resolves in a packaged app. Ad-hoc signs so it launches cleanly.
set -e
cd "$(dirname "$0")/../desktop"
VERSION="${VERSION:-$(cut -d. -f1-3 VERSION)}"

echo "› swift build -c release"
swift build -c release >/dev/null

APP="../Hexlens.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/MacLeagueOverlay "$APP/Contents/MacOS/Hexlens"

# Resource bundles — in Contents/Resources (= Bundle.main.resourceURL, where Bundle.module
# resolves first for app bundles, and the codesign-clean location).
for b in .build/release/*.bundle; do
  cp -R "$b" "$APP/Contents/Resources/"
done

# App icon from icon-1024.png (best effort).
ICONLINE=""
if [ -f ../icon-1024.png ]; then
  ICONSET="$(mktemp -d)/AppIcon.iconset"; mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s ../icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null 2>&1 || true
    sips -z $((s*2)) $((s*2)) ../icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null 2>&1 || true
  done
  if iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null; then
    ICONLINE="<key>CFBundleIconFile</key><string>AppIcon</string>"
  fi
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>Hexlens</string>
  <key>CFBundleIdentifier</key><string>com.hexlens.app</string>
  <key>CFBundleName</key><string>Hexlens</string>
  <key>CFBundleDisplayName</key><string>Hexlens</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  ${ICONLINE}
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSInputMonitoringUsageDescription</key>
  <string>Hexlens reads the Tab key to show the overlay while League of Legends is active.</string>
  <key>NSAccessibilityUsageDescription</key>
  <string>Hexlens uses accessibility to monitor the Tab hotkey while League of Legends is active.</string>
</dict>
</plist>
PLIST

# Ad-hoc codesign (required to launch on Apple Silicon; stable bundle id keeps TCC permissions
# across rebuilds). SPM resource bundles are NOT code bundles, so sign WITHOUT --deep — the outer
# app seals them as plain resources. Clean perms/xattrs/old signatures first or codesign rejects it.
chmod -R u+w "$APP"
find "$APP" -name '*.xcprivacy' -exec chmod u+w {} \; 2>/dev/null || true
xattr -cr "$APP" 2>/dev/null || true
find "$APP" -name '_CodeSignature' -type d -exec rm -rf {} + 2>/dev/null || true
codesign --force -s - --identifier com.hexlens.app "$APP"
codesign --verify "$APP" && echo "✓ signature valid"

echo "✓ Built $(cd "$(dirname "$APP")" && pwd)/Hexlens.app"
