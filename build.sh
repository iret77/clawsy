#!/bin/bash
set -e

# Config
APP_NAME="Clawsy"
BUILD_DIR=".build"
RELEASE_DIR="$BUILD_DIR/release"
APP_BUNDLE="$BUILD_DIR/app/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "🧹 Cleaning up..."
rm -rf "$APP_BUNDLE"

echo "🎨 Generating Icons..."
if [ -f "scripts/generate_icons.sh" ]; then
    chmod +x scripts/generate_icons.sh
    ./scripts/generate_icons.sh || echo "⚠️ Icon generation skipped/failed"
fi

echo "🦞 Building Clawsy (Release)..."
if ! command -v swift &> /dev/null; then
    echo "❌ Error: 'swift' command not found."
    exit 1
fi

swift build -c release --arch arm64 --arch x86_64

echo "📦 Packaging $APP_NAME.app..."
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy Binary
cp "$RELEASE_DIR/$APP_NAME" "$MACOS_DIR/"

# Copy Info.plist
if [ -f "Info.plist" ]; then
    cp "Info.plist" "$CONTENTS_DIR/"
else
    echo "⚠️ Info.plist not found!"
fi

# Compile Assets (macOS only)
if command -v actool &> /dev/null; then
    echo "🖼 Compiling Assets.xcassets..."
    actool "Sources/Clawsy/Assets.xcassets" --compile "$RESOURCES_DIR" --platform macosx --minimum-deployment-target 13.0 --app-icon AppIcon --output-partial-info-plist "$BUILD_DIR/assets.plist" > /dev/null
else
    echo "⚠️ 'actool' not found (linux?). Skipping asset compilation."
fi

echo "✅ Build successful!"
echo "📂 App Bundle: $APP_BUNDLE"
