#!/bin/bash
set -e

# Config
APP_NAME="Clawsy"
SCHEME="ClawsyMac"
BUILD_DIR=".build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
APP_BUNDLE="$BUILD_DIR/app/$APP_NAME.app"
SIGN_ID="${CODESIGN_IDENTITY:--}"

# Always enable Hardened Runtime. Without it, macOS 14+ silently kills
# the app when accessing TCC-protected resources (camera, screen
# recording) — no crash report, just a SIGKILL.
#
# The com.apple.security.cs.disable-library-validation entitlement
# allows loading frameworks signed with a different (or self-signed)
# identity, so this works even with ad-hoc / self-signed certificates.
HARDENED_RUNTIME=YES

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

# ── Step 5: Verify CLAWSY.md ───────────────────────────────────────
# CLAWSY.md is included via project.yml resources — no manual copy
# needed. Copying after xcodebuild would break the code signature seal.
if [ -f "$APP_BUNDLE/Contents/Resources/CLAWSY.md" ]; then
    echo "✅ CLAWSY.md bundled by xcodebuild"
else
    echo "⚠️  CLAWSY.md missing from bundle resources"
fi

# ── Step 6: Re-sign bundle for consistent Team ID ─────────────────
# Re-sign all components with the same identity (inside-out) to
# guarantee matching Team IDs. Without this, dyld may refuse to load
# the framework ("mapping process and mapped file have different
# Team IDs"). --preserve-metadata keeps entitlements from xcodebuild.
echo "🔏 Re-signing app bundle (component-level)..."

if [ "$HARDENED_RUNTIME" = "YES" ]; then
    # Apple cert: preserve entitlements + flags (including runtime flag)
    CODESIGN_ARGS="--preserve-metadata=entitlements,identifier,flags"
else
    # Self-signed / ad-hoc: preserve entitlements but NOT flags to avoid
    # re-introducing the hardened runtime flag that causes dyld rejection
    CODESIGN_ARGS="--preserve-metadata=entitlements,identifier"
fi

# 6a: Frameworks
for fw in "$APP_BUNDLE"/Contents/Frameworks/*.framework; do
    [ -d "$fw" ] && codesign --force --sign "$SIGN_ID" $CODESIGN_ARGS "$fw"
done

# 6b: Extensions
for ext in "$APP_BUNDLE"/Contents/PlugIns/*.appex; do
    [ -d "$ext" ] && codesign --force --sign "$SIGN_ID" $CODESIGN_ARGS "$ext"
done

# 6c: Main app (outermost, signed last)
codesign --force --sign "$SIGN_ID" $CODESIGN_ARGS "$APP_BUNDLE"

# ── Step 7: Verify ──────────────────────────────────────────────────
echo "🔍 Verifying bundle structure..."

# Check extensions are embedded
if [ -d "$APP_BUNDLE/Contents/PlugIns/ClawsyShare.appex" ]; then
    echo "✅ Share Extension embedded"
else
    echo "⚠️  Share Extension missing from PlugIns/"
fi

if [ -d "$APP_BUNDLE/Contents/PlugIns/ClawsyFinderSync.appex" ]; then
    echo "✅ FinderSync Extension embedded"
else
    echo "⚠️  FinderSync Extension missing from PlugIns/"
fi

# Verify code signature
codesign -vvv --deep --strict "$APP_BUNDLE"

# Verify extension entitlements are preserved
echo "🔐 Verifying extension entitlements..."
if codesign -d --entitlements :- "$APP_BUNDLE/Contents/PlugIns/ClawsyFinderSync.appex" 2>/dev/null | grep -q "FinderSync.HostBundleIdentifier"; then
    echo "✅ FinderSync entitlements OK"
else
    echo "⚠️  FinderSync missing HostBundleIdentifier entitlement!"
fi
if codesign -d --entitlements :- "$APP_BUNDLE/Contents/PlugIns/ClawsyShare.appex" 2>/dev/null | grep -q "application-groups"; then
    echo "✅ Share Extension entitlements OK"
else
    echo "⚠️  Share Extension missing app-group entitlement!"
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
