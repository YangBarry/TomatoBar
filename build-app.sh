#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

echo "==> Building TomatoBar (Release)..."
swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
APP_BUNDLE="$PROJECT_DIR/TomatoBar.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_DIR/TomatoBar" "$MACOS_DIR/TomatoBar"
chmod +x "$MACOS_DIR/TomatoBar"

# Copy SPM resource bundles
for bundle in "$BIN_DIR"/*.bundle; do
    if [ -d "$bundle" ]; then
        cp -R "$bundle" "$RESOURCES_DIR/"
    fi
done

# Copy localization folders directly into Resources as well
for lproj in TomatoBar/*.lproj; do
    if [ -d "$lproj" ]; then
        cp -R "$lproj" "$RESOURCES_DIR/"
    fi
done

# Copy audio assets
cp TomatoBar/Assets.xcassets/windup.dataset/windup.wav "$RESOURCES_DIR/windup.wav"
cp TomatoBar/Assets.xcassets/ding.dataset/ding.wav "$RESOURCES_DIR/ding.wav"
cp TomatoBar/Assets.xcassets/ticking.dataset/ticking.wav "$RESOURCES_DIR/ticking.wav"

# Copy menu bar icons (1x, 2x, 3x)
for icon in BarIconIdle BarIconWork BarIconShortRest BarIconLongRest; do
    cp "TomatoBar/Assets.xcassets/${icon}.imageset/icon_16x16.png" "$RESOURCES_DIR/${icon}.png"
    cp "TomatoBar/Assets.xcassets/${icon}.imageset/icon_16x16@2x.png" "$RESOURCES_DIR/${icon}@2x.png"
    cp "TomatoBar/Assets.xcassets/${icon}.imageset/icon_16x16@3x.png" "$RESOURCES_DIR/${icon}@3x.png"
done

# Build AppIcon.icns using iconutil
ICONSET_TMP="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET_TMP"
cp TomatoBar/Assets.xcassets/AppIcon.appiconset/icon_*.png "$ICONSET_TMP/"
iconutil -c icns "$ICONSET_TMP" -o "$RESOURCES_DIR/AppIcon.icns"
rm -rf "$(dirname "$ICONSET_TMP")"

# Generate Info.plist
cat > "$CONTENTS_DIR/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh-Hans</string>
    <key>CFBundleExecutable</key>
    <string>TomatoBar</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.github.ivoronin.TomatoBar.custom</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>TomatoBar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>3.1.0</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>TomatoBar uses AppleScript to play and pause your Lofi Girl playlist in Apple Music during focus and break sessions.</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>CFBundleURLName</key>
            <string>com.github.ivoronin.TomatoBar.custom</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>tomatobar</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
EOF

codesign --force --deep --sign - "$APP_BUNDLE"
rm -rf "/Applications/TomatoBar.app"
cp -R "$APP_BUNDLE" "/Applications/TomatoBar.app"
echo "==> Successfully built: $APP_BUNDLE (and synced to /Applications/TomatoBar.app)"
