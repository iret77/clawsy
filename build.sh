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

# ── Step 1b: Dump entitlements files as CI actually sees them ──────
# Confirms the checkout state — separates "CI saw wrong files" from
# "CI saw right files but xcodebuild stripped them anyway".
echo ""
echo "🔬 Entitlements files at build time (CI's view):"
for ent in ClawsyMac.entitlements \
           Sources/ClawsyMacShare/ClawsyMacShare.entitlements \
           Sources/ClawsyFinderSync/ClawsyFinderSync.entitlements; do
    if [ -f "$ent" ]; then
        echo "  --- $ent ($(wc -c < "$ent" | tr -d ' ') bytes) ---"
        sed 's/^/    /' "$ent"
    else
        echo "  ❌ MISSING: $ent"
    fi
done
echo ""

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

# ── Step 3b: Dump intermediate xcent files (productPackagingUtility output) ─
# These are the entitlements xcodebuild fed to codesign during archive.
# If application-groups is missing here, productPackagingUtility stripped it
# (entitlements file or build-mode problem). If it's present here but absent
# from the final bundle, codesign stripped it (cert/profile/entitlement
# mismatch problem). The archive intermediate path differs from plain build.
echo ""
echo "🔬 xcent files (input to codesign during archive):"
for xcent in "$DERIVED_DATA"/Build/Intermediates.noindex/ArchiveIntermediates/ClawsyMac/IntermediateBuildFilesPath/Clawsy.build/Release/*.build/*.xcent; do
    [ -f "$xcent" ] || continue
    echo "  --- $(basename "$xcent") ---"
    cat "$xcent" | python3 -c "
import sys, plistlib
d = plistlib.loads(sys.stdin.buffer.read() or b'<plist><dict/></plist>')
for k,v in (d or {}).items():
    print(f'    {k} = {v}')"
done
echo ""

# Also dump the entitlements on the ARCHIVE-internal bundle (pre-export) to
# distinguish whether archive signed correctly and exportArchive stripped, or
# whether archive itself never had them.
ARCHIVE_APP="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
if [ -d "$ARCHIVE_APP" ]; then
    echo "🔬 Entitlements on archive-internal bundle (before exportArchive):"
    for component in "$ARCHIVE_APP/Contents/PlugIns/ClawsyShare.appex" \
                     "$ARCHIVE_APP/Contents/PlugIns/ClawsyFinderSync.appex" \
                     "$ARCHIVE_APP"; do
        [ -d "$component" ] || continue
        echo "  --- $(basename "$component") ---"
        codesign -d --entitlements :- "$component" 2>/dev/null \
          | python3 -c "import sys,plistlib; d=plistlib.loads(sys.stdin.buffer.read() or b'<plist><dict/></plist>'); print('\n'.join('    '+k for k in d.keys()) if d else '    (empty)')"
    done
    echo ""
fi

# ── Step 3c: Manual re-sign with explicit entitlements ─────────────
# Workaround for Apple's productPackagingUtility bug: in distribution mode it
# emits xcent files containing only application-identifier + team-identifier,
# silently dropping all .entitlements file contents (app-sandbox,
# application-groups, FinderSync.HostBundleIdentifier).  codesign then signs
# bundles with the (empty) xcent.  Re-sign each component pointing codesign
# directly at the .entitlements file.  This works only because the bundle now
# has a correct embedded.provisionprofile that allowlists those entitlements;
# without a profile, Apple-issued cert would strip them.
#
# Sign order: innermost first (frameworks → extensions → host).
if [ "$DISTRIBUTION_BUILD" = "YES" ]; then
    echo ""
    echo "🔏 Re-signing components with explicit entitlements..."
    CS_OPTS="--force --options runtime --timestamp --generate-entitlement-der"

    # Frameworks (no entitlements file, just propagate cert/runtime)
    for fw in "$APP_BUNDLE"/Contents/Frameworks/*.framework; do
        [ -d "$fw" ] || continue
        echo "  → $(basename "$fw")"
        codesign $CS_OPTS --sign "$SIGN_ID" "$fw"
    done

    # Share Extension
    echo "  → ClawsyShare.appex (with ClawsyMacShare.entitlements)"
    codesign $CS_OPTS \
        --entitlements Sources/ClawsyMacShare/ClawsyMacShare.entitlements \
        --sign "$SIGN_ID" \
        "$APP_BUNDLE/Contents/PlugIns/ClawsyShare.appex"

    # FinderSync Extension
    echo "  → ClawsyFinderSync.appex (with ClawsyFinderSync.entitlements)"
    codesign $CS_OPTS \
        --entitlements Sources/ClawsyFinderSync/ClawsyFinderSync.entitlements \
        --sign "$SIGN_ID" \
        "$APP_BUNDLE/Contents/PlugIns/ClawsyFinderSync.appex"

    # Host (last, so it seals over the now-correctly-signed extensions)
    echo "  → Clawsy.app (with ClawsyMac.entitlements)"
    codesign $CS_OPTS \
        --entitlements ClawsyMac.entitlements \
        --sign "$SIGN_ID" \
        "$APP_BUNDLE"
    echo ""
fi

# ── Step 4: Verify CLAWSY.md ───────────────────────────────────────
if [ -f "$APP_BUNDLE/Contents/Resources/CLAWSY.md" ]; then
    echo "✅ CLAWSY.md bundled by xcodebuild"
else
    echo "⚠️  CLAWSY.md missing from bundle resources"
fi

# ── Step 5: Diagnostic dump ────────────────────────────────────────
echo ""
echo "🔬 Diagnostic — codesign details:"
for component in "$APP_BUNDLE/Contents/PlugIns/ClawsyShare.appex" \
                 "$APP_BUNDLE/Contents/PlugIns/ClawsyFinderSync.appex" \
                 "$APP_BUNDLE"; do
    [ -d "$component" ] || continue
    echo "  --- $(basename "$component") ---"
    codesign -dvv "$component" 2>&1 | grep -E "^(Identifier|TeamIdentifier|Authority|Runtime Version)" | sed 's/^/    /' || true
    if [ -f "$component/Contents/embedded.provisionprofile" ]; then
        echo "    Embedded Profile: yes ($(stat -f%z "$component/Contents/embedded.provisionprofile") bytes)"
    else
        echo "    Embedded Profile: NO"
    fi
    echo "    --- entitlements (XML form, codesign -d --entitlements :-): ---"
    codesign -d --entitlements :- "$component" 2>&1 | sed 's/^/      /' || true
    echo "    --- entitlements (DER form, codesign -d --entitlements-der :-): ---"
    codesign -d --entitlements-der :- "$component" 2>&1 | head -30 | sed 's/^/      /' || true
    echo ""
done
echo ""

# ── Step 6: Verify ──────────────────────────────────────────────────
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

    verify_ent "$APP_BUNDLE/Contents/PlugIns/ClawsyFinderSync.appex" "FinderSync.HostBundleIdentifier" "FinderSync"
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
