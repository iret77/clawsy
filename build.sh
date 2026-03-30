#!/bin/bash
set -e

# Config
APP_NAME="Clawsy"
SCHEME="ClawsyMac"
BUILD_DIR=".build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
APP_BUNDLE="$BUILD_DIR/app/$APP_NAME.app"
SIGN_ID="${CODESIGN_IDENTITY:--}"

echo "🔑 Signing identity: $SIGN_ID"

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
    ENABLE_HARDENED_RUNTIME=YES \
    build

# ── Step 4: Copy built .app to output directory ─────────────────────
echo "📦 Packaging $APP_NAME.app..."
BUILT_APP=$(find "$DERIVED_DATA" -name "$APP_NAME.app" -type d -path "*/Release/*" | head -n 1)

if [ -z "$BUILT_APP" ]; then
    echo "❌ Error: Could not find built app bundle"
    exit 1
fi

cp -R "$BUILT_APP" "$APP_BUNDLE"

# ── Step 5: Bundle CLAWSY.md ────────────────────────────────────────
if [ -f "CLAWSY.md" ]; then
    cp "CLAWSY.md" "$APP_BUNDLE/Contents/Resources/CLAWSY.md"
    echo "✅ Bundled CLAWSY.md"
fi

# ── Step 6: Re-sign if needed ──────────────────────────────────────
# When xcodebuild uses a named identity (e.g. "Clawsy Development"),
# it already signs each component with its entitlements correctly.
# Re-signing would strip entitlements. Only re-sign for ad-hoc (-).
if [ "$SIGN_ID" = "-" ]; then
    echo "🔏 Ad-hoc identity — re-signing bundle components..."

    codesign --force --sign - "$APP_BUNDLE/Contents/Frameworks/ClawsyShared.framework"

    codesign --force --sign - \
        --entitlements "Sources/ClawsyMacShare/ClawsyMacShare.entitlements" \
        "$APP_BUNDLE/Contents/PlugIns/ClawsyShare.appex"

    codesign --force --sign - \
        --entitlements "Sources/ClawsyFinderSync/ClawsyFinderSync.entitlements" \
        "$APP_BUNDLE/Contents/PlugIns/ClawsyFinderSync.appex"

    codesign --force --sign - \
        --entitlements "ClawsyMac.entitlements" \
        "$APP_BUNDLE"
else
    echo "🔏 Named identity '$SIGN_ID' — xcodebuild signatures preserved"
fi

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

# Show signing identity
echo "🔑 Signing details:"
codesign -dvv "$APP_BUNDLE/Contents/PlugIns/ClawsyFinderSync.appex" 2>&1 | grep -E "^(Authority|TeamIdentifier|Signature)" || true

echo ""
echo "✅ Build successful!"
echo "📂 App Bundle: $APP_BUNDLE"
