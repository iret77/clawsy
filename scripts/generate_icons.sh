#!/bin/bash
set -e

SOURCE_MENU="Assets/Icon.png"
SOURCE_APP="Assets/AppIcon.jpg"
DEST="Sources/Clawsy/Assets.xcassets/AppIcon.appiconset"

# Create Dest Dir if needed
mkdir -p "$DEST"

if ! command -v sips &> /dev/null; then
    echo "⚠️  'sips' command not found. This is expected on Linux, but FATAL on macOS CI."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "❌ Error: sips missing on macOS!"
        exit 1
    else
        # Mock for local/linux dev to prevent script failure
        for size in 16 32 64 128 256 512 1024; do
            touch "$DEST/icon_${size}x${size}.png"
        done
        exit 0
    fi
fi

if [ ! -f "$SOURCE_APP" ]; then
    echo "❌ Error: Source AppIcon not found at $SOURCE_APP"
    exit 1
fi

echo "🎨 Generating App Icons from $SOURCE_APP..."

# Generate App Icons for Finder from the color JPG
# Force output to PNG so iconutil is happy
sips -s format png -z 16 16     "$SOURCE_APP" --out "$DEST/icon_16x16.png" > /dev/null
sips -s format png -z 32 32     "$SOURCE_APP" --out "$DEST/icon_16x16@2x.png" > /dev/null
sips -s format png -z 32 32     "$SOURCE_APP" --out "$DEST/icon_32x32.png" > /dev/null
sips -s format png -z 64 64     "$SOURCE_APP" --out "$DEST/icon_32x32@2x.png" > /dev/null
sips -s format png -z 128 128   "$SOURCE_APP" --out "$DEST/icon_128x128.png" > /dev/null
sips -s format png -z 256 256   "$SOURCE_APP" --out "$DEST/icon_128x128@2x.png" > /dev/null
sips -s format png -z 256 256   "$SOURCE_APP" --out "$DEST/icon_256x256.png" > /dev/null
sips -s format png -z 512 512   "$SOURCE_APP" --out "$DEST/icon_256x256@2x.png" > /dev/null
sips -s format png -z 512 512   "$SOURCE_APP" --out "$DEST/icon_512x512.png" > /dev/null
sips -s format png -z 1024 1024 "$SOURCE_APP" --out "$DEST/icon_512x512@2x.png" > /dev/null

echo "✅ App Icons generated as PNG!"
