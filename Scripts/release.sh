#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="Aqua Voice Hook"
BUNDLE_ID="com.aqua-voice-hook.app"
INFO_PLIST="$PROJECT_DIR/Sources/AquaVoiceHook/Info.plist"
ENTITLEMENTS="$PROJECT_DIR/Sources/AquaVoiceHook/Entitlements.plist"
IDENTITY="Developer ID Application: Micah Alpern (X2RKZ5TG99)"
NOTARY_PROFILE="KeyPath-Profile"

# Find sign_update
SIGN_UPDATE="$(ls -1dt /opt/homebrew/Caskroom/sparkle/*/bin/sign_update 2>/dev/null | head -1 || true)"
if [[ -z "$SIGN_UPDATE" ]]; then
    echo "❌ sign_update not found. Install Sparkle: brew install --cask sparkle"
    exit 1
fi

DRY_RUN=false
SKIP_NOTARIZE=false
NEW_VERSION=""

for arg in "$@"; do
    case $arg in
        --dry-run) DRY_RUN=true ;;
        --skip-notarize) SKIP_NOTARIZE=true ;;
        *)
            if [[ $arg =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
                NEW_VERSION="$arg"
            else
                echo "Usage: $0 [--dry-run] [--skip-notarize] [X.Y.Z]"
                exit 1
            fi
            ;;
    esac
done

cd "$PROJECT_DIR"

CURRENT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")
echo "🚀 Aqua Voice Hook Release"
echo "=========================="
echo "📌 Current version: $CURRENT_VERSION"

if [[ -n "$NEW_VERSION" ]]; then
    echo "📝 Bumping to: $NEW_VERSION"
    if [[ "$DRY_RUN" == false ]]; then
        /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW_VERSION" "$INFO_PLIST"
        /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_VERSION" "$INFO_PLIST"
    fi
    VERSION="$NEW_VERSION"
else
    VERSION="$CURRENT_VERSION"
fi

echo "🎯 Release version: $VERSION"
echo ""

if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY RUN] Would: build → sign → notarize → package → tag → release → appcast"
    exit 0
fi

# Build
echo "🔨 Building release..."
swift build -c release 2>&1 | tail -3
BINARY="$(swift build -c release --show-bin-path)/AquaVoiceHook"

# Assemble app bundle
echo "📦 Assembling app bundle..."
APP_DIR="dist/${APP_NAME}.app"
rm -rf dist
mkdir -p "dist" "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BINARY" "$APP_DIR/Contents/MacOS/AquaVoiceHook"
cp "$INFO_PLIST" "$APP_DIR/Contents/Info.plist"
cp "$PROJECT_DIR/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

# Copy Sparkle framework into app bundle
SPARKLE_FRAMEWORK="$(swift build -c release --show-bin-path)/../../../checkouts/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ -d "$SPARKLE_FRAMEWORK" ]]; then
    mkdir -p "$APP_DIR/Contents/Frameworks"
    cp -R "$SPARKLE_FRAMEWORK" "$APP_DIR/Contents/Frameworks/"
    echo "   Copied Sparkle.framework"
fi

# Sign
echo "🔏 Code signing..."
# Sign frameworks first
if [[ -d "$APP_DIR/Contents/Frameworks/Sparkle.framework" ]]; then
    codesign --force --sign "$IDENTITY" --options runtime --timestamp \
        "$APP_DIR/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc" 2>/dev/null || true
    codesign --force --sign "$IDENTITY" --options runtime --timestamp \
        "$APP_DIR/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc" 2>/dev/null || true
    codesign --force --sign "$IDENTITY" --options runtime --timestamp \
        "$APP_DIR/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate" 2>/dev/null || true
    codesign --force --sign "$IDENTITY" --options runtime --timestamp \
        "$APP_DIR/Contents/Frameworks/Sparkle.framework" 2>/dev/null || true
fi
# Sign the main app
codesign --force --sign "$IDENTITY" --options runtime --entitlements "$ENTITLEMENTS" --timestamp "$APP_DIR"
echo "   ✅ Signed"

# Notarize
if [[ "$SKIP_NOTARIZE" == false ]]; then
    echo "📋 Notarizing..."
    ZIP_FOR_NOTARY="dist/AquaVoiceHook-notarize.zip"
    ditto -c -k --keepParent "$APP_DIR" "$ZIP_FOR_NOTARY"
    xcrun notarytool submit "$ZIP_FOR_NOTARY" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP_DIR"
    rm "$ZIP_FOR_NOTARY"
    echo "   ✅ Notarized and stapled"
else
    echo "⚠️  Skipping notarization"
fi

# Create Sparkle ZIP
echo "📦 Creating Sparkle archive..."
SPARKLE_ZIP="dist/AquaVoiceHook-${VERSION}.zip"
ditto -c -k --keepParent "$APP_DIR" "$SPARKLE_ZIP"

# Sign with EdDSA
echo "🔑 Signing with EdDSA..."
EDDSA_OUTPUT=$("$SIGN_UPDATE" "$SPARKLE_ZIP" 2>&1)
echo "   $EDDSA_OUTPUT"

# Extract signature and length for appcast
EDDSA_SIG=$(echo "$EDDSA_OUTPUT" | grep -o 'sparkle:edSignature="[^"]*"' | cut -d'"' -f2)
FILE_SIZE=$(stat -f%z "$SPARKLE_ZIP")

# Generate appcast entry
APPCAST_ENTRY="dist/AquaVoiceHook-${VERSION}.appcast-entry.xml"
DOWNLOAD_URL="https://github.com/malpern/aqua-voice-hook/releases/download/v${VERSION}/AquaVoiceHook-${VERSION}.zip"
PUB_DATE=$(date -R)

cat > "$APPCAST_ENTRY" <<ENTRY
        <item>
            <title>Version ${VERSION}</title>
            <pubDate>${PUB_DATE}</pubDate>
            <enclosure
                url="${DOWNLOAD_URL}"
                sparkle:version="${VERSION}"
                sparkle:shortVersionString="${VERSION}"
                sparkle:edSignature="${EDDSA_SIG}"
                length="${FILE_SIZE}"
                type="application/octet-stream"
            />
        </item>
ENTRY
echo "   ✅ Appcast entry generated"

# Update appcast.xml
echo "📝 Updating appcast.xml..."
python3 -c "
appcast = open('appcast.xml').read()
entry = open('$APPCAST_ENTRY').read()
marker = '<!-- Releases go here (newest first) -->'
if marker in appcast:
    appcast = appcast.replace(marker, marker + '\n\n' + entry.rstrip())
    open('appcast.xml', 'w').write(appcast)
    print('   ✅ Appcast updated')
else:
    print('   ⚠️  Marker not found — update manually')
"

# Git tag
echo "🏷️  Tagging v${VERSION}..."
git add -A
git commit -m "chore: release v${VERSION}"
git tag "v${VERSION}"

# GitHub Release
echo "📤 Creating GitHub Release..."
gh release create "v${VERSION}" \
    "$SPARKLE_ZIP" \
    --title "Aqua Voice Hook ${VERSION}" \
    --notes "See release notes."

# Push
echo "📤 Pushing..."
git push origin master --tags

echo ""
echo "✅ Release v${VERSION} complete!"
echo ""
echo "📦 Artifacts:"
echo "   • $APP_DIR"
echo "   • $SPARKLE_ZIP"
echo "   • $APPCAST_ENTRY"
echo ""
echo "🔗 https://github.com/malpern/aqua-voice-hook/releases/tag/v${VERSION}"
