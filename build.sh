#!/bin/bash
set -e

# Config
BINARY_NAME="ClawsyMac"
APP_NAME="Clawsy"
BUILD_DIR=".build"
RELEASE_DIR="$BUILD_DIR/apple/Products/Release"
APP_BUNDLE="$BUILD_DIR/app/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
PLUGINS_DIR="$CONTENTS_DIR/PlugIns"
SHARE_EXT_BUNDLE="$PLUGINS_DIR/ClawsyShare.appex"

echo "🧹 Cleaning up..."
rm -rf "$APP_BUNDLE"

echo "🦞 Building Clawsy Ecosystem (Release)..."
if ! command -v swift &> /dev/null; then
    echo "❌ Error: 'swift' command not found."
    exit 1
fi

# Build everything for both architectures
swift build -c release --arch arm64 --arch x86_64

echo "📦 Packaging $APP_NAME.app..."
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"
mkdir -p "$SHARE_EXT_BUNDLE/Contents/MacOS"

# 1. Copy Main Binary and RENAME to Clawsy
if [ -f "$RELEASE_DIR/$BINARY_NAME" ]; then
    cp "$RELEASE_DIR/$BINARY_NAME" "$MACOS_DIR/$APP_NAME"
    chmod 755 "$MACOS_DIR/$APP_NAME"
else
    echo "❌ Error: Main binary not found at $RELEASE_DIR/$BINARY_NAME"
    exit 1
fi

# 2. Copy Share Extension Binary
if [ -f "$RELEASE_DIR/libClawsyMacShare.dylib" ]; then
    cp "$RELEASE_DIR/libClawsyMacShare.dylib" "$SHARE_EXT_BUNDLE/Contents/MacOS/ClawsyShare"
    chmod 755 "$SHARE_EXT_BUNDLE/Contents/MacOS/ClawsyShare"
elif [ -f "$RELEASE_DIR/ClawsyMacShare" ]; then
     cp "$RELEASE_DIR/ClawsyMacShare" "$SHARE_EXT_BUNDLE/Contents/MacOS/ClawsyShare"
     chmod 755 "$SHARE_EXT_BUNDLE/Contents/MacOS/ClawsyShare"
fi

# 3. Create a robust Info.plist
cat <<EOF > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>ai.clawsy</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.2.3</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>CFBundleVersion</key>
    <string>123</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

if [ -f "Sources/ClawsyMacShare/Info.plist" ]; then
    cp "Sources/ClawsyMacShare/Info.plist" "$SHARE_EXT_BUNDLE/Contents/"
fi

# 4. Icon Generation & Packaging
echo "🎨 Packaging Icons..."
if [ -f "scripts/generate_icons.sh" ]; then
    chmod +x scripts/generate_icons.sh
    ./scripts/generate_icons.sh
fi

# Manual ICNS creation with improved robustness
if command -v iconutil &> /dev/null; then
    ICONSET_DIR="$BUILD_DIR/Clawsy.iconset"
    mkdir -p "$ICONSET_DIR"
    
    # Map our generated PNGs to the standard iconset naming convention
    cp "Sources/ClawsyMac/Assets.xcassets/AppIcon.appiconset/icon_16x16.png" "$ICONSET_DIR/icon_16x16.png" || true
    cp "Sources/ClawsyMac/Assets.xcassets/AppIcon.appiconset/icon_32x32.png" "$ICONSET_DIR/icon_16x16@2x.png" || true
    cp "Sources/ClawsyMac/Assets.xcassets/AppIcon.appiconset/icon_32x32.png" "$ICONSET_DIR/icon_32x32.png" || true
    cp "Sources/ClawsyMac/Assets.xcassets/AppIcon.appiconset/icon_64x64.png" "$ICONSET_DIR/icon_32x32@2x.png" || true
    cp "Sources/ClawsyMac/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" "$ICONSET_DIR/icon_128x128.png" || true
    cp "Sources/ClawsyMac/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" "$ICONSET_DIR/icon_128x128@2x.png" || true
    cp "Sources/ClawsyMac/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" "$ICONSET_DIR/icon_256x256.png" || true
    cp "Sources/ClawsyMac/Assets.xcassets/AppIcon.appiconset/icon_512x512.png" "$ICONSET_DIR/icon_256x256@2x.png" || true
    cp "Sources/ClawsyMac/Assets.xcassets/AppIcon.appiconset/icon_512x512.png" "$ICONSET_DIR/icon_512x512.png" || true
    cp "Sources/ClawsyMac/Assets.xcassets/AppIcon.appiconset/icon_1024x1024.png" "$ICONSET_DIR/icon_512x512@2x.png" || true
    
    iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns" || echo "⚠️ iconutil failed, falling back to actool only"
fi

# Compile Assets.car
if command -v actool &> /dev/null; then
    actool "Sources/ClawsyMac/Assets.xcassets" --compile "$RESOURCES_DIR" --platform macosx --minimum-deployment-target 13.0 --app-icon AppIcon --output-partial-info-plist "$BUILD_DIR/assets.plist" > /dev/null
fi

# 5. Link Shared Resources
mkdir -p "$RESOURCES_DIR/en.lproj"
mkdir -p "$RESOURCES_DIR/de.lproj"
cp Sources/ClawsyShared/Resources/en.lproj/Localizable.strings "$RESOURCES_DIR/en.lproj/"
cp Sources/ClawsyShared/Resources/de.lproj/Localizable.strings "$RESOURCES_DIR/de.lproj/"

echo "🛡 Signing (Ad-hoc)..."
if [ -d "$SHARE_EXT_BUNDLE" ]; then
    echo "Signing Extension Binary..."
    codesign --force --options runtime --entitlements Sources/ClawsyMacShare/ClawsyMacShare.entitlements --sign - "$SHARE_EXT_BUNDLE/Contents/MacOS/ClawsyShare"
    echo "Signing Extension Bundle..."
    codesign --force --options runtime --entitlements Sources/ClawsyMacShare/ClawsyMacShare.entitlements --sign - "$SHARE_EXT_BUNDLE"
fi

echo "Signing Main Binary..."
codesign --force --options runtime --entitlements ClawsyMac.entitlements --sign - "$MACOS_DIR/$APP_NAME"

echo "Signing App Bundle..."
codesign --force --deep --options runtime --entitlements ClawsyMac.entitlements --sign - "$APP_BUNDLE"

echo "✅ Build successful!"
echo "📂 App Bundle: $APP_BUNDLE"
