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

# 2. Copy Share Extension Binary (dylib used as Plugin)
# In recent builds it's libClawsyMacShare.dylib
if [ -f "$RELEASE_DIR/libClawsyMacShare.dylib" ]; then
    cp "$RELEASE_DIR/libClawsyMacShare.dylib" "$SHARE_EXT_BUNDLE/Contents/MacOS/ClawsyShare"
    chmod 755 "$SHARE_EXT_BUNDLE/Contents/MacOS/ClawsyShare"
elif [ -f "$RELEASE_DIR/ClawsyMacShare" ]; then
     cp "$RELEASE_DIR/ClawsyMacShare" "$SHARE_EXT_BUNDLE/Contents/MacOS/ClawsyShare"
     chmod 755 "$SHARE_EXT_BUNDLE/Contents/MacOS/ClawsyShare"
fi

# 3. Handle Icons and Assets
if [ -f "scripts/generate_icons.sh" ]; then
    chmod +x scripts/generate_icons.sh
    ./scripts/generate_icons.sh
fi

ICONSET_DIR="$BUILD_DIR/Clawsy.iconset"
mkdir -p "$ICONSET_DIR"
SRC_ICONS="Sources/ClawsyMac/Assets.xcassets/AppIcon.appiconset"
for size in 16 32 128 256 512; do
    cp "$SRC_ICONS/icon_${size}x${size}.png" "$ICONSET_DIR/icon_${size}x${size}.png" || true
    double=$((size * 2))
    if [ "$size" -ne "512" ]; then
        cp "$SRC_ICONS/icon_${double}x${double}.png" "$ICONSET_DIR/icon_${size}x${size}@2x.png" || true
    else
        cp "$SRC_ICONS/icon_1024x1024.png" "$ICONSET_DIR/icon_512x512@2x.png" || true
    fi
done

if command -v iconutil &> /dev/null; then
    echo "Creating AppIcon.icns..."
    iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"
fi

if command -v actool &> /dev/null; then
    actool "Sources/ClawsyMac/Assets.xcassets" \
        --compile "$RESOURCES_DIR" \
        --platform macosx \
        --minimum-deployment-target 13.0 \
        --app-icon AppIcon \
        --output-partial-info-plist "$BUILD_DIR/partial.plist"
fi

# 📦 Embedding Resource Bundles (CRITICAL FIX FOR CRASH)
SHARED_BUNDLE=$(find "$BUILD_DIR" -name "Clawsy_ClawsyShared.bundle" -type d | head -n 1)
if [ -d "$SHARED_BUNDLE" ]; then
    cp -R "$SHARED_BUNDLE" "$RESOURCES_DIR/"
fi

# 4. Create PkgInfo
echo -n "APPL????" > "$CONTENTS_DIR/PkgInfo"

# 5. Create Final Info.plist
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
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>CFBundleVersion</key>
    <string>153</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

if [ -f "$BUILD_DIR/partial.plist" ] && command -v /usr/libexec/PlistBuddy &> /dev/null; then
    /usr/libexec/PlistBuddy -c "Merge $BUILD_DIR/partial.plist" "$CONTENTS_DIR/Info.plist"
fi

# 6. Share Extension Info.plist
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

# 7. Copy Localizations
mkdir -p "$RESOURCES_DIR/en.lproj"
mkdir -p "$RESOURCES_DIR/de.lproj"
cp Sources/ClawsyShared/Resources/en.lproj/Localizable.strings "$RESOURCES_DIR/en.lproj/"
cp Sources/ClawsyShared/Resources/de.lproj/Localizable.strings "$RESOURCES_DIR/de.lproj/"

echo "🛡 Signing (Ad-hoc)..."
if [ -f "$SHARE_EXT_BUNDLE/Contents/MacOS/ClawsyShare" ]; then
    codesign --force --options runtime --entitlements Sources/ClawsyMacShare/ClawsyMacShare.entitlements --sign - "$SHARE_EXT_BUNDLE/Contents/MacOS/ClawsyShare"
    codesign --force --options runtime --entitlements Sources/ClawsyMacShare/ClawsyMacShare.entitlements --sign - "$SHARE_EXT_BUNDLE"
fi
codesign --force --options runtime --entitlements ClawsyMac.entitlements --sign - "$MACOS_DIR/$APP_NAME"
codesign --force --deep --options runtime --entitlements ClawsyMac.entitlements --sign - "$APP_BUNDLE"

# Verification
codesign -vvv --deep --strict "$APP_BUNDLE"

echo "✅ Build successful!"
echo "📂 App Bundle: $APP_BUNDLE"
