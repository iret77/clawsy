#!/bin/bash
# Clawsy Update Installer (Hot-Swap)
# Usage: ./update_installer.sh <path_to_new_app> <target_app_path>

NEW_APP="$1"
TARGET_APP="$2"
BUNDLE_ID="ai.clawsy"

if [ -z "$NEW_APP" ] || [ -z "$TARGET_APP" ]; then
    echo "Usage: $0 <new_app_path> <target_app_path>"
    exit 1
fi

echo "🦞 Clawsy Updater: Starting..."

# 1. Kill running instance
echo "🔪 Killing existing Clawsy instances..."
pkill -x "Clawsy" || true

# 2. Swap Apps
echo "📦 Swapping app bundles..."
rm -rf "$TARGET_APP"
mv "$NEW_APP" "$TARGET_APP"

# 3. Fix Permissions (Quarantine)
echo "🛡️ Removing quarantine attributes..."
xattr -cr "$TARGET_APP"

# 4. Reset TCC (Critical for new signature/binary)
echo "🔐 Resetting Privacy Permissions..."
tccutil reset ScreenCapture "$BUNDLE_ID" || true
tccutil reset Microphone "$BUNDLE_ID" || true
tccutil reset Accessibility "$BUNDLE_ID" || true

# 5. Relaunch
echo "🚀 Relaunching..."
open "$TARGET_APP"

echo "✅ Update complete."
exit 0
