#!/bin/bash
set -e

# Config
APP_NAME="ClawsyMac"
BUILD_DIR=".build"
RELEASE_DIR="$BUILD_DIR/release"
APP_BUNDLE="$BUILD_DIR/app/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
PLUGINS_DIR="$CONTENTS_DIR/PlugIns"
SHARE_EXT_BUNDLE="$PLUGINS_DIR/ClawsyShare.appex"

echo "🧹 Cleaning up..."
rm -rf "$APP_BUNDLE"

echo "🎨 Generating Icons..."
if [ -f "scripts/generate_icons.sh" ]; then
    chmod +x scripts/generate_icons.sh
    ./scripts/generate_icons.sh || echo "⚠️ Icon generation skipped/failed"
fi

echo "🦞 Building Clawsy Ecosystem (Release)..."
if ! command -v swift &> /dev/null; then
    echo "❌ Error: 'swift' command not found."
    exit 1
fi

# Build everything
swift build -c release --arch arm64 --arch x86_64

echo "📦 Packaging $APP_NAME.app..."
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"
mkdir -p "$SHARE_EXT_BUNDLE/Contents/MacOS"

# Copy Main Binary
cp "$RELEASE_DIR/ClawsyMac" "$MACOS_DIR/$APP_NAME"

# Copy Share Extension Binary (dylib to executable)
if [ -f "$RELEASE_DIR/libClawsyMacShare.dylib" ]; then
    cp "$RELEASE_DIR/libClawsyMacShare.dylib" "$SHARE_EXT_BUNDLE/Contents/MacOS/ClawsyShare"
elif [ -f "$RELEASE_DIR/ClawsyMacShare" ]; then
     cp "$RELEASE_DIR/ClawsyMacShare" "$SHARE_EXT_BUNDLE/Contents/MacOS/ClawsyShare"
fi

# Copy Info.plists
if [ -f "Info.plist" ]; then
    cp "Info.plist" "$CONTENTS_DIR/"
fi
if [ -f "Sources/ClawsyMacShare/Info.plist" ]; then
    cp "Sources/ClawsyMacShare/Info.plist" "$SHARE_EXT_BUNDLE/Contents/"
fi

# Compile Assets
if command -v actool &> /dev/null; then
    echo "🖼 Compiling Assets.xcassets..."
    actool "Sources/ClawsyMac/Assets.xcassets" --compile "$RESOURCES_DIR" --platform macosx --minimum-deployment-target 13.0 --app-icon AppIcon --output-partial-info-plist "$BUILD_DIR/assets.plist" > /dev/null
fi

# Link Shared Resources (Localizable.strings)
mkdir -p "$RESOURCES_DIR/en.lproj"
mkdir -p "$RESOURCES_DIR/de.lproj"
cp Sources/ClawsyShared/Resources/en.lproj/Localizable.strings "$RESOURCES_DIR/en.lproj/"
cp Sources/ClawsyShared/Resources/de.lproj/Localizable.strings "$RESOURCES_DIR/de.lproj/"

echo "🛡 Signing (Ad-hoc)..."
if [ -f "Sources/ClawsyMacShare/ClawsyMacShare.entitlements" ]; then
    codesign --force --options runtime --entitlements Sources/ClawsyMacShare/ClawsyMacShare.entitlements --sign - "$SHARE_EXT_BUNDLE"
fi
codesign --force --options runtime --entitlements ClawsyMac.entitlements --sign - "$APP_BUNDLE"

echo "✅ Build successful!"
echo "📂 App Bundle: $APP_BUNDLE"
echo "🚀 To test: Move to /Applications and enable 'Clawsy Share' in System Settings > Extensions"
