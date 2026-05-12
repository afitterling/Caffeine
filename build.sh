#!/usr/bin/env bash
# Build BreakTimer and assemble a runnable .app bundle next to it.
# Usage: ./build.sh         (builds into ./BreakTimer.app)
#        ./build.sh install (also copies into ~/Applications)
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="BreakTimer"
BUNDLE="${APP_NAME}.app"
BUNDLE_ID="local.alex.breaktimer"

echo "→ Building release binary…"
swift build -c release

BIN=".build/release/${APP_NAME}"
test -x "$BIN" || { echo "Build failed: $BIN missing"; exit 1; }

echo "→ Assembling ${BUNDLE}…"
rm -rf "$BUNDLE"
mkdir -p "${BUNDLE}/Contents/MacOS"
mkdir -p "${BUNDLE}/Contents/Resources"
cp "$BIN" "${BUNDLE}/Contents/MacOS/${APP_NAME}"

cat > "${BUNDLE}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>            <string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key>     <string>${APP_NAME}</string>
  <key>CFBundleExecutable</key>      <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>      <string>${BUNDLE_ID}</string>
  <key>CFBundleVersion</key>         <string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key>     <string>APPL</string>
  <key>LSMinimumSystemVersion</key>  <string>13.0</string>
  <key>LSUIElement</key>             <true/>
  <key>NSHumanReadableCopyright</key><string>Local build</string>
</dict>
</plist>
PLIST

# Ad-hoc sign so Gatekeeper/quarantine doesn't refuse to launch a freshly
# built bundle from Finder. -f overwrites any prior signature.
codesign --force --deep --sign - "$BUNDLE" >/dev/null 2>&1 || true

echo "✓ Built ${PWD}/${BUNDLE}"

if [[ "${1:-}" == "install" ]]; then
  DEST="${HOME}/Applications"
  mkdir -p "$DEST"
  rm -rf "${DEST}/${BUNDLE}"
  cp -R "$BUNDLE" "$DEST/"
  echo "✓ Installed to ${DEST}/${BUNDLE}"
  echo "  Open it with:  open \"${DEST}/${BUNDLE}\""
else
  echo "  Run it with:  open \"${PWD}/${BUNDLE}\""
fi
