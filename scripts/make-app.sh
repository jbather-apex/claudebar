#!/bin/bash
# Builds ClaudeBar.app from the SwiftPM binary. Notifications and
# launch-at-login require a real bundle, hence this script.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP=dist/ClaudeBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/ClaudeBar "$APP/Contents/MacOS/ClaudeBar"
cp Assets/AppIcon.icns Assets/MenuBarIcon.png "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ClaudeBar</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.jbather.claudebar</string>
    <key>CFBundleName</key>
    <string>ClaudeBar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>ClaudeBar focuses the terminal tab running a Claude session when you click it.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"

echo "Built $PWD/$APP"
echo "Run:  open $PWD/$APP"
