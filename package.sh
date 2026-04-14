#!/bin/bash

set -euo pipefail

APP_NAME="SideNote.app"
APP_CONTENTS="$APP_NAME/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
ZIP_NAME="SideNote.app.zip"

swift build -c release

rm -rf "$APP_NAME" "$ZIP_NAME"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"

cp ".build/release/SideNote" "$APP_MACOS/SideNote"
cp "SideNote.icns" "$APP_RESOURCES/AppIcon.icns"
cp "avatar.png" "$APP_RESOURCES/avatar.png"

cat > "$APP_CONTENTS/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>SideNote</string>
    <key>CFBundleIdentifier</key>
    <string>com.liwu.SideNote</string>
    <key>CFBundleName</key>
    <string>SideNote</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
EOF

ditto -c -k --sequesterRsrc --keepParent "$APP_NAME" "$ZIP_NAME"

echo "Created $ZIP_NAME"
