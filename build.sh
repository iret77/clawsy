#!/bin/bash
set -e

# Config
APP_NAME="Clawsy"
SCHEME="ClawsyMac"
BUILD_DIR=".build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
APP_BUNDLE="$BUILD_DIR/app/$APP_NAME.app"
SIGN_ID="${CODESIGN_IDENTITY:--}"

# Hardened Runtime requires an Apple-issued certificate (Developer ID /
# Apple Development).  The `disable-library-validation` entitlement that
# would allow loading self-signed frameworks is a *restricted* entitlement
# — macOS silently ignores it when the cert is not Apple-issued.  Result:
# dyld kills the app at launch ("different Team IDs").
#
# Enable HR only when the signing identity is a real Apple cert.
case "$SIGN_ID" in
    "Developer ID"*|"Apple Development"*|"Apple Distribution"*|"3rd Party Mac"*)
        HARDENED_RUNTIME=YES ;;
    *)
        HARDENED_RUNTIME=NO ;;
esac

echo "🔑 Signing identity: $SIGN_ID"
echo "🛡️  Hardened Runtime: $HARDENED_RUNTIME"

echo "🧹 Cleaning up..."
rm -rf "$BUILD_DIR/app"
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

# ── Step 3: Build with xcodebuild ───────────────────────────────────
echo "🦞 Building $APP_NAME (Release, Universal)..."
xcodebuild \
    -project Clawsy.xcodeproj \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    -arch arm64 -arch x86_64 \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_IDENTITY="$SIGN_ID" \
    CODE_SIGN_STYLE=Manual \
    ENABLE_HARDENED_RUNTIME=$HARDENED_RUNTIME \
    build

# ── Step 4: Copy built .app to output directory ─────────────────────
echo "📦 Packaging $APP_NAME.app..."
BUILT_APP=$(find "$DERIVED_DATA" -name "$APP_NAME.app" -type d -path "*/Release/*" | head -n 1)

if [ -z "$BUILT_APP" ]; then
    echo "❌ Error: Could not find built app bundle"
    exit 1
fi

cp -R "$BUILT_APP" "$APP_BUNDLE"

# ── Step 4b: Dump xcent files xcodebuild handed to codesign ────────
# These are the merged entitlements (`.entitlements` + profile defaults
# via productPackagingUtility) that get fed to codesign --entitlements.
# If application-groups is missing here, it's a profile-merge filter
# problem; if it's present, codesign is the one stripping it.
echo ""
echo "🔬 xcent files (productPackagingUtility output, fed to codesign):"
for xcent in "$DERIVED_DATA"/Build/Intermediates.noindex/Clawsy.build/Release/*.build/*.xcent; do
    [ -f "$xcent" ] || continue
    echo "  --- $(basename "$xcent") ---"
    cat "$xcent" | python3 -c "
import sys, plistlib
d = plistlib.loads(sys.stdin.buffer.read() or b'<plist><dict/></plist>')
for k,v in (d or {}).items():
    print(f'    {k} = {v}')"
done
echo ""

# ── Step 5: Verify CLAWSY.md ───────────────────────────────────────
# CLAWSY.md is included via project.yml resources — no manual copy
# needed. Copying after xcodebuild would break the code signature seal.
if [ -f "$APP_BUNDLE/Contents/Resources/CLAWSY.md" ]; then
    echo "✅ CLAWSY.md bundled by xcodebuild"
else
    echo "⚠️  CLAWSY.md missing from bundle resources"
fi

# ── Step 6: Re-sign frameworks for consistent Team ID ──────────────
# xcodebuild already signed Host + both Extensions correctly via
# PROVISIONING_PROFILE_SPECIFIER (Profile-aware path that retains
# restricted entitlements). We only re-sign Swift Package framework
# products here, because xcodebuild signs those with a build-internal
# identity that doesn't carry our Team ID.
echo "🔏 Re-signing third-party frameworks for Team-ID consistency..."

if [ "$HARDENED_RUNTIME" = "YES" ]; then
    CODESIGN_OPTS="--options runtime --timestamp --generate-entitlement-der"
else
    CODESIGN_OPTS="--generate-entitlement-der"
fi

for fw in "$APP_BUNDLE"/Contents/Frameworks/*.framework; do
    [ -d "$fw" ] || continue
    for bundle in "$fw"/Versions/A/Resources/*.bundle; do
        [ -d "$bundle" ] && codesign --force --sign "$SIGN_ID" $CODESIGN_OPTS "$bundle"
    done
    codesign --force --sign "$SIGN_ID" $CODESIGN_OPTS "$fw"
done

# ── Step 6d: Diagnostic dump ───────────────────────────────────────
# Surface what's actually in each bundle's signature so future failures
# don't require pulling the artifact + manual codesign -d to debug.
echo ""
echo "🔬 Diagnostic — codesign details:"
for component in "$APP_BUNDLE/Contents/PlugIns/ClawsyShare.appex" \
                 "$APP_BUNDLE/Contents/PlugIns/ClawsyFinderSync.appex" \
                 "$APP_BUNDLE"; do
    echo "  --- $(basename "$component") ---"
    codesign -dvv "$component" 2>&1 | grep -E "^(Identifier|TeamIdentifier|Authority|Runtime Version)" | sed 's/^/    /' || true
    if [ -f "$component/Contents/embedded.provisionprofile" ]; then
        echo "    Embedded Profile: yes ($(stat -f%z "$component/Contents/embedded.provisionprofile") bytes)"
    else
        echo "    Embedded Profile: NO"
    fi
    echo "    entitlement keys:"
    codesign -d --entitlements :- "$component" 2>/dev/null \
      | python3 -c "import sys,plistlib; d=plistlib.loads(sys.stdin.buffer.read() or b'<plist><dict/></plist>'); print('\n'.join('      '+k for k in d.keys()) if d else '      (empty)')"
done
echo ""

# ── Step 7: Verify ──────────────────────────────────────────────────
echo "🔍 Verifying bundle structure..."

# Check extensions are embedded
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

# Verify entitlements survived signing — these are HARD failures.
# An empty <dict/> at this point means codesign dropped restricted
# entitlements (no provisioning profile embedded, or wrong cert).
echo "🔐 Verifying entitlements survived re-sign..."
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
    echo "❌ One or more components are missing required entitlements after re-sign."
    echo "   This is the silent-fail mode (Apple cert + missing/invalid provisioning profile)."
    exit 1
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
