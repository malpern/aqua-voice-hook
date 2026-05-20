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

# Find Sparkle tools
SPARKLE_BIN="$(ls -1dt /opt/homebrew/Caskroom/sparkle/*/bin 2>/dev/null | head -1 || true)"
if [[ -z "$SPARKLE_BIN" ]] || [[ ! -x "$SPARKLE_BIN/generate_appcast" ]]; then
    echo "❌ Sparkle tools not found. Install: brew install --cask sparkle"
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
install_name_tool -add_rpath @executable_path/../Frameworks "$APP_DIR/Contents/MacOS/AquaVoiceHook" 2>/dev/null || true
cp "$INFO_PLIST" "$APP_DIR/Contents/Info.plist"
cp "$PROJECT_DIR/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

# Copy Sparkle framework into app bundle
SPARKLE_FRAMEWORK="$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ -d "$SPARKLE_FRAMEWORK" ]]; then
    mkdir -p "$APP_DIR/Contents/Frameworks"
    cp -R "$SPARKLE_FRAMEWORK" "$APP_DIR/Contents/Frameworks/"
    echo "   Copied Sparkle.framework"
fi

# Sign
echo "🔏 Code signing..."
# Sign all Sparkle components (innermost first)
if [[ -d "$APP_DIR/Contents/Frameworks/Sparkle.framework" ]]; then
    find "$APP_DIR/Contents/Frameworks/Sparkle.framework" \( -name "*.xpc" -o -name "*.app" -o -name "Autoupdate" \) -print0 | while IFS= read -r -d '' component; do
        codesign --force --sign "$IDENTITY" --options runtime --timestamp "$component"
    done
    codesign --force --sign "$IDENTITY" --options runtime --timestamp \
        "$APP_DIR/Contents/Frameworks/Sparkle.framework"
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

# Generate appcast with EdDSA signing
echo "🔑 Generating appcast with EdDSA signatures..."
DOWNLOAD_URL_PREFIX="https://github.com/malpern/aqua-voice-hook/releases/download/v${VERSION}"
"$SPARKLE_BIN/generate_appcast" \
    --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
    -o appcast.xml \
    dist/
echo "   ✅ Appcast generated"

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
