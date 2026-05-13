#!/bin/bash
set -e

# Config
APP_NAME="Clawsy"
SCHEME="ClawsyMac"
BUILD_DIR=".build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
APP_BUNDLE="$BUILD_DIR/app/$APP_NAME.app"
EXPORT_OPTIONS="ExportOptions.plist"
SIGN_ID="${CODESIGN_IDENTITY:--}"

# Distribution build = archive + exportArchive (Apple's required path for
# Developer ID Direct Distribution).  Local/dev builds with ad-hoc cert use
# plain `xcodebuild build` because archive requires a real cert in the keychain
# and the productPackagingUtility distribution-mode would reject ad-hoc anyway.
case "$SIGN_ID" in
    "Developer ID"*|"Apple Development"*|"Apple Distribution"*|"3rd Party Mac"*)
        DISTRIBUTION_BUILD=YES ;;
    *)
        DISTRIBUTION_BUILD=NO ;;
esac

echo "🔑 Signing identity: $SIGN_ID"
echo "📦 Distribution build: $DISTRIBUTION_BUILD"

echo "🧹 Cleaning up..."
rm -rf "$BUILD_DIR/app" "$ARCHIVE_PATH" "$EXPORT_PATH"
mkdir -p "$BUILD_DIR/app"

# ── Step 1: Generate Xcode project from project.yml ─────────────────
if ! command -v xcodegen &> /dev/null; then
    echo "📦 Installing XcodeGen..."
    brew install xcodegen
fi

echo "🔧 Generating Xcode project..."
xcodegen generate --spec project.yml

# ── Step 2: Generate icons from source assets ──────────────────────
echo "🎨 Generating icons..."
bash scripts/generate_icons.sh

# ── Step 3: Build ───────────────────────────────────────────────────
if [ "$DISTRIBUTION_BUILD" = "YES" ]; then
    # Apple Developer ID Direct Distribution path: archive then exportArchive.
    # Plain `xcodebuild build` produces .xcent files that contain ONLY profile
    # defaults (application-identifier, team-identifier, get-task-allow=YES)
    # because Xcode treats it as a development build — restricted entitlements
    # (application-groups, FinderSync.HostBundleIdentifier) get silently
    # stripped before codesign even runs.  Archive sets ENTITLEMENTS_REQUIRED
    # and PROVISIONING_PROFILE_REQUIRED to YES, switching productPackagingUtility
    # into distribution mode, which honors the full .entitlements files.
    echo "🦞 Archiving $APP_NAME (Release, Universal)..."
    xcodebuild \
        -project Clawsy.xcodeproj \
        -scheme "$SCHEME" \
        -configuration Release \
        -derivedDataPath "$DERIVED_DATA" \
        -archivePath "$ARCHIVE_PATH" \
        -arch arm64 -arch x86_64 \
        ONLY_ACTIVE_ARCH=NO \
        CODE_SIGN_IDENTITY="$SIGN_ID" \
        CODE_SIGN_STYLE=Manual \
        archive

    echo "📤 Exporting archive with developer-id method..."
    xcodebuild \
        -archivePath "$ARCHIVE_PATH" \
        -exportArchive \
        -exportPath "$EXPORT_PATH" \
        -exportOptionsPlist "$EXPORT_OPTIONS"

    if [ ! -d "$EXPORT_PATH/$APP_NAME.app" ]; then
        echo "❌ Error: exportArchive did not produce $APP_NAME.app"
        ls -la "$EXPORT_PATH" || true
        exit 1
    fi

    cp -R "$EXPORT_PATH/$APP_NAME.app" "$APP_BUNDLE"
else
    # Local/dev ad-hoc path — no distribution semantics, just produce a runnable
    # bundle. Restricted entitlements will be stripped by codesign, but for
    # local dev that's fine; macOS treats ad-hoc-signed unsandboxed apps
    # leniently.
    echo "🦞 Building $APP_NAME (Release, Universal, ad-hoc)..."
    xcodebuild \
        -project Clawsy.xcodeproj \
        -scheme "$SCHEME" \
        -configuration Release \
        -derivedDataPath "$DERIVED_DATA" \
        -arch arm64 -arch x86_64 \
        ONLY_ACTIVE_ARCH=NO \
        CODE_SIGN_IDENTITY="$SIGN_ID" \
        CODE_SIGN_STYLE=Manual \
        ENABLE_HARDENED_RUNTIME=NO \
        PROVISIONING_PROFILE_SPECIFIER="" \
        build

    BUILT_APP=$(find "$DERIVED_DATA" -name "$APP_NAME.app" -type d -path "*/Release/*" | head -n 1)
    if [ -z "$BUILT_APP" ]; then
        echo "❌ Error: Could not find built app bundle"
        exit 1
    fi
    cp -R "$BUILT_APP" "$APP_BUNDLE"
fi

# ── Step 4: Verify CLAWSY.md ───────────────────────────────────────
if [ -f "$APP_BUNDLE/Contents/Resources/CLAWSY.md" ]; then
    echo "✅ CLAWSY.md bundled by xcodebuild"
else
    echo "⚠️  CLAWSY.md missing from bundle resources"
fi

# ── Step 5: Verify ──────────────────────────────────────────────────
echo "🔍 Verifying bundle structure..."

if [ -d "$APP_BUNDLE/Contents/PlugIns/ClawsyShare.appex" ]; then
    echo "✅ Share Extension embedded"
else
    echo "❌ Share Extension missing from PlugIns/" && exit 1
fi

if [ -d "$APP_BUNDLE/Contents/PlugIns/ClawsyFinderSync.appex" ]; then
    echo "✅ FinderSync Extension embedded"
else
    echo "❌ FinderSync Extension missing from PlugIns/" && exit 1
fi

# Verify code signature
codesign -vvv --deep --strict "$APP_BUNDLE"

# Verify restricted entitlements survived signing — these are HARD failures
# for distribution builds.  In ad-hoc local builds we skip these because
# codesign strips them by design.
if [ "$DISTRIBUTION_BUILD" = "YES" ]; then
    echo "🔐 Verifying entitlements survived signing..."
    ENT_FAIL=0

    verify_ent() {
        local bundle="$1" needle="$2" label="$3"
        local ent
        ent=$(codesign -d --entitlements :- "$bundle" 2>/dev/null)
        if echo "$ent" | grep -q "$needle"; then
            echo "  ✅ $label has $needle"
        else
            echo "  ❌ $label is MISSING $needle"
            ENT_FAIL=1
        fi
    }

    verify_ent "$APP_BUNDLE/Contents/PlugIns/ClawsyFinderSync.appex" "application-groups"             "FinderSync"
    verify_ent "$APP_BUNDLE/Contents/PlugIns/ClawsyShare.appex"      "application-groups"             "Share Extension"
    verify_ent "$APP_BUNDLE"                                         "application-groups"             "Host"

    if [ "$ENT_FAIL" != "0" ]; then
        echo "❌ One or more components are missing required entitlements."
        exit 1
    fi
fi

# Show signing identity & Team ID for all components
echo "🔑 Signing details:"
for component in "$APP_BUNDLE" "$APP_BUNDLE"/Contents/Frameworks/*.framework "$APP_BUNDLE"/Contents/PlugIns/*.appex; do
    [ -e "$component" ] || continue
    echo "  $(basename "$component"):"
    codesign -dvv "$component" 2>&1 | grep -E "^(Authority|TeamIdentifier|Identifier)" | sed 's/^/    /' || true
done

echo ""
echo "✅ Build successful!"
echo "📂 App Bundle: $APP_BUNDLE"
