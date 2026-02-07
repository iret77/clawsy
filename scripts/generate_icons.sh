#!/bin/bash
set -e

SOURCE="Assets/Icon.png"
DEST="Sources/Clawsy/Assets.xcassets/AppIcon.appiconset"

echo "🔍 Debug: Current Dir: $(pwd)"
echo "🔍 Debug: Checking Source: $SOURCE"
ls -l "$SOURCE" || echo "❌ Source file listing failed"

if [ ! -f "$SOURCE" ]; then
    echo "❌ Error: No source icon found at $SOURCE"
    echo "📂 Directory listing:"
    ls -R
    exit 1
fi

# Create Dest Dir if needed
mkdir -p "$DEST"

if ! command -v sips &> /dev/null; then
    echo "⚠️  'sips' command not found. This is expected on Linux, but FATAL on macOS CI."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "❌ Error: sips missing on macOS!"
        exit 1
    else
        exit 0
    fi
fi

echo "🎨 Generating App Icons from $SOURCE..."

# Sizes needed: 16, 32, 64 (32@2x), 128, 256, 512, 1024
sips -z 16 16     "$SOURCE" --out "$DEST/icon_16x16.png" > /dev/null
sips -z 32 32     "$SOURCE" --out "$DEST/icon_16x16@2x.png" > /dev/null
sips -z 32 32     "$SOURCE" --out "$DEST/icon_32x32.png" > /dev/null
sips -z 64 64     "$SOURCE" --out "$DEST/icon_32x32@2x.png" > /dev/null
sips -z 128 128   "$SOURCE" --out "$DEST/icon_128x128.png" > /dev/null
sips -z 256 256   "$SOURCE" --out "$DEST/icon_128x128@2x.png" > /dev/null
sips -z 256 256   "$SOURCE" --out "$DEST/icon_256x256.png" > /dev/null
sips -z 512 512   "$SOURCE" --out "$DEST/icon_256x256@2x.png" > /dev/null
sips -z 512 512   "$SOURCE" --out "$DEST/icon_512x512.png" > /dev/null
sips -z 1024 1024 "$SOURCE" --out "$DEST/icon_512x512@2x.png" > /dev/null

echo "✅ Icons generated!"
