#!/bin/bash
set -e

# Configuration
APP_NAME="Clawsy"
APP_BUNDLE=".build/app/$APP_NAME.app"
ZIP_PATH=".build/$APP_NAME.zip"
SIGNING_IDENTITY="Developer ID Application: Christian (YOUR_TEAM_ID)" # Update this!
NOTARY_PROFILE="AC_PASSWORD" # Profile name from 'xcrun notarytool store-credentials'

# Check for tools
if ! command -v codesign &> /dev/null; then
    echo "❌ Error: 'codesign' not found."
    exit 1
fi

echo "🔐 Signing $APP_NAME.app..."
codesign --force --options runtime --deep --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
codesign --verify --verbose=4 "$APP_BUNDLE"

echo "📦 Zipping for notarization..."
/usr/bin/ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "🛡 Notarizing..."
xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

echo "✅ Notarization complete. Stapling ticket..."
xcrun stapler staple "$APP_BUNDLE"

echo "🎉 Done! Ready for distribution."
