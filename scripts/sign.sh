#!/bin/bash
set -e

# Configuration
APP_NAME="Clawsy"
APP_BUNDLE=".build/app/$APP_NAME.app"

echo "🔐 Ad-hoc signing $APP_NAME.app..."
# Using '-' for ad-hoc signing since we don't have a developer identity here
codesign --force --options runtime --deep --sign "-" "$APP_BUNDLE"

echo "✅ Ad-hoc signing complete."
echo "⚠️ Note: You may still need to right-click -> Open to bypass Gatekeeper (unnotarized)."
