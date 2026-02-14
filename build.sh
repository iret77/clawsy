#!/bin/bash
set -e

# Config
BINARY_NAME="ClawsyMac"
APP_NAME="Clawsy"
BUNDLE_ID="ai.clawsy"
BUILD_DIR=".build"
RELEASE_DIR="$BUILD_DIR/apple/Products/Release"
APP_BUNDLE="$BUILD_DIR/app/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
PLUGINS_DIR="$CONTENTS_DIR/PlugIns"
SHARE_EXT_BUNDLE="$PLUGINS_DIR/ClawsyShare.appex"

echo "🧹 Cleaning up..."
rm -rf "$BUILD_DIR/app"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"
mkdir -p "$SHARE_EXT_BUNDLE/Contents/MacOS"
mkdir -p "$SHARE_EXT_BUNDLE/Contents/Resources"

echo "🦞 Building Clawsy Ecosystem (Release)..."
# Build for universal
swift build -c release --arch arm64 --arch x86_64

echo "📦 Packaging $APP_NAME.app..."

# 1. Copy Main Binary
cp "$RELEASE_DIR/$BINARY_NAME" "$MACOS_DIR/$APP_NAME"
chmod 755 "$MACOS_DIR/$APP_NAME"

# 2. Copy Share Extension Binary
if [ -f "$RELEASE_DIR/libClawsyMacShare.dylib" ]; then
    cp "$RELEASE_DIR/libClawsyMacShare.dylib" "$SHARE_EXT_BUNDLE/Contents/MacOS/ClawsyShare"
elif [ -f "$RELEASE_DIR/ClawsyMacShare" ]; then
     cp "$RELEASE_DIR/ClawsyMacShare" "$SHARE_EXT_BUNDLE/Contents/MacOS/ClawsyShare"
fi
chmod 755 "$SHARE_EXT_BUNDLE/Contents/MacOS/ClawsyShare"

# 3. Handle Icons and Assets
echo "🎨 Packaging Icons and Assets..."
if [ -f "scripts/generate_icons.sh" ]; then
    chmod +x scripts/generate_icons.sh
    ./scripts/generate_icons.sh
fi

# Create a proper .icns for the Finder
if command -v iconutil &> /dev/null; then
    ICONSET_DIR="$BUILD_DIR/Clawsy.iconset"
    mkdir -p "$ICONSET_DIR"
    cp Sources/ClawsyMac/Assets.xcassets/AppIcon.appiconset/icon_16x16.png "$ICONSET_DIR/icon_16x16.png" || true
    cp Sources/ClawsyMac/Assets.xcassets/AppIcon.appiconset/icon_32x32.png "$ICONSET_DIR/icon_16x16@2x.png" || true
    cp Sources/ClawsyMac/Assets.xcassets/AppIcon.appiconset/icon_32x32.png "$ICONSET_DIR/icon_32x32.png" || true
    cp Sources/ClawsyMac/Assets.xcassets/AppIcon.appiconset/icon_64x64.png "$ICONSET_DIR/icon_32x32@2x.png" || true
    cp Sources/ClawsyMac/Assets.xcassets/AppIcon.appiconset/icon_128x128.png "$ICONSET_DIR/icon_128x128.png" || true
    cp Sources/ClawsyMac/Assets.xcassets/AppIcon.appiconset/icon_256x256.png "$ICONSET_DIR/icon_128x128@2x.png" || true
    cp Sources/ClawsyMac/Assets.xcassets/AppIcon.appiconset/icon_256x256.png "$ICONSET_DIR/icon_256x256.png" || true
    cp Sources/ClawsyMac/Assets.xcassets/AppIcon.appiconset/icon_512x512.png "$ICONSET_DIR/icon_256x256@2x.png" || true
    cp Sources/ClawsyMac/Assets.xcassets/AppIcon.appiconset/icon_512x512.png "$ICONSET_DIR/icon_512x512.png" || true
    cp Sources/ClawsyMac/Assets.xcassets/AppIcon.appiconset/icon_1024x1024.png "$ICONSET_DIR/icon_512x512@2x.png" || true
    iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"
fi

# Compile Assets.car
if command -v actool &> /dev/null; then
    actool "Sources/ClawsyMac/Assets.xcassets" \
        --compile "$RESOURCES_DIR" \
        --platform macosx \
        --minimum-deployment-target 13.0 \
        --app-icon AppIcon \
        --output-partial-info-plist "$BUILD_DIR/partial.plist"
fi

# 4. Create Main Info.plist
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
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.2.3</string>
    <key>CFBundleVersion</key>
    <string>126</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

if [ -f "$BUILD_DIR/partial.plist" ] && command -v /usr/libexec/PlistBuddy &> /dev/null; then
    /usr/libexec/PlistBuddy -c "Merge $BUILD_DIR/partial.plist" "$CONTENTS_DIR/Info.plist"
fi

# 5. Create Share Extension Info.plist
cat <<EOF > "$SHARE_EXT_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ClawsyShare</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID.ShareExtension</string>
    <key>CFBundleName</key>
    <string>Clawsy Share</string>
    <key>CFBundlePackageType</key>
    <string>XPC!</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleShortVersionString</key>
    <string>0.2.3</string>
    <key>CFBundleVersion</key>
    <string>126</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionAttributes</key>
        <dict>
            <key>NSExtensionActivationRule</key>
            <string>TRUEPREDICATE</string>
        </dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.share-services</string>
        <key>NSExtensionPrincipalClass</key>
        <string>ClawsyMacShare.ShareViewController</string>
    </dict>
</dict>
</plist>
EOF

# 6. Copy Localizations
mkdir -p "$RESOURCES_DIR/en.lproj"
mkdir -p "$RESOURCES_DIR/de.lproj"
cp Sources/ClawsyShared/Resources/en.lproj/Localizable.strings "$RESOURCES_DIR/en.lproj/"
cp Sources/ClawsyShared/Resources/de.lproj/Localizable.strings "$RESOURCES_DIR/de.lproj/"

echo "🛡 Signing (Ad-hoc)..."
# Inside-out signing
if [ -f "$SHARE_EXT_BUNDLE/Contents/MacOS/ClawsyShare" ]; then
    codesign --force --options runtime --entitlements Sources/ClawsyMacShare/ClawsyMacShare.entitlements --sign - "$SHARE_EXT_BUNDLE/Contents/MacOS/ClawsyShare"
fi
codesign --force --options runtime --entitlements Sources/ClawsyMacShare/ClawsyMacShare.entitlements --sign - "$SHARE_EXT_BUNDLE"
codesign --force --options runtime --entitlements ClawsyMac.entitlements --sign - "$MACOS_DIR/$APP_NAME"
codesign --force --deep --options runtime --entitlements ClawsyMac.entitlements --sign - "$APP_BUNDLE"

echo "✅ Build successful!"
echo "📂 App Bundle: $APP_BUNDLE"
