#!/bin/bash
# Clawsy Installer & Un-Quarantine Script
# Usage: ./install_clawsy.sh path/to/Clawsy.app.zip

ZIP_FILE=$1

if [ -z "$ZIP_FILE" ]; then
    echo "Usage: ./install_clawsy.sh <path-to-zip>"
    exit 1
fi

echo "🦞 Unpacking Clawsy..."
unzip -o "$ZIP_FILE" -d /Applications/

APP_PATH="/Applications/Clawsy.app"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ Error: App not found at $APP_PATH"
    exit 1
fi

echo "🔓 Removing Quarantine & Gatekeeper attributes..."
sudo xattr -cr "$APP_PATH"
sudo codesign --force --deep --sign - "$APP_PATH"

echo "🚀 Launching Clawsy..."
open "$APP_PATH"

echo "✅ Enjoy the Lobster! 🦞"
