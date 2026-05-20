#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="Aqua Voice Hook"
BUNDLE_ID="com.aqua-voice-hook"
APP_DIR="/Applications/${APP_NAME}.app"
LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
LAUNCH_AGENT="$LAUNCH_AGENT_DIR/${BUNDLE_ID}.plist"
IDENTITY="Developer ID Application: Micah Alpern (X2RKZ5TG99)"
ENTITLEMENTS="$PROJECT_DIR/Sources/AquaVoiceHook/Entitlements.plist"

echo "=== Building Aqua Voice Hook ==="
cd "$PROJECT_DIR"
swift build -c release 2>&1 | tail -5

BINARY="$(swift build -c release --show-bin-path)/AquaVoiceHook"
if [[ ! -f "$BINARY" ]]; then
    echo "ERROR: Build failed — binary not found"
    exit 1
fi

echo ""
echo "=== Assembling app bundle ==="
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$APP_DIR/Contents/Frameworks"

cp "$BINARY" "$APP_DIR/Contents/MacOS/AquaVoiceHook"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP_DIR/Contents/MacOS/AquaVoiceHook" 2>/dev/null || true
cp "$PROJECT_DIR/Sources/AquaVoiceHook/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$PROJECT_DIR/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

# Copy Sparkle framework
SPARKLE_FRAMEWORK="$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ -d "$SPARKLE_FRAMEWORK" ]]; then
    cp -R "$SPARKLE_FRAMEWORK" "$APP_DIR/Contents/Frameworks/"
    echo "  Copied Sparkle.framework"
fi

echo "  Installed: $APP_DIR"

echo ""
echo "=== Code signing ==="
# Sign all Sparkle components (innermost first)
if [[ -d "$APP_DIR/Contents/Frameworks/Sparkle.framework" ]]; then
    find "$APP_DIR/Contents/Frameworks/Sparkle.framework" \( -name "*.xpc" -o -name "*.app" -o -name "Autoupdate" \) -print0 | while IFS= read -r -d '' component; do
        codesign --force --sign "$IDENTITY" --options runtime --timestamp "$component"
    done
    codesign --force --sign "$IDENTITY" --options runtime --timestamp \
        "$APP_DIR/Contents/Frameworks/Sparkle.framework"
fi
codesign --force --sign "$IDENTITY" --options runtime --entitlements "$ENTITLEMENTS" --timestamp "$APP_DIR"
echo "  Signed with Developer ID"

echo ""
echo "=== Installing LaunchAgent ==="
launchctl bootout "gui/$(id -u)/$BUNDLE_ID" 2>/dev/null || true

mkdir -p "$LAUNCH_AGENT_DIR"
cp "$PROJECT_DIR/LaunchAgent/${BUNDLE_ID}.plist" "$LAUNCH_AGENT"

launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT"
echo "  LaunchAgent loaded: $BUNDLE_ID"

echo ""
echo "=== Ensuring config directory ==="
mkdir -p "$HOME/.config/aqua-voice-hook/hooks"
if [[ ! -f "$HOME/.config/aqua-voice-hook/config.json" ]]; then
    echo "  Created default config"
else
    echo "  Config exists: ~/.config/aqua-voice-hook/config.json"
fi

if [[ -d "$PROJECT_DIR/hooks" ]] && [[ -z "$(ls -A "$HOME/.config/aqua-voice-hook/hooks" 2>/dev/null)" ]]; then
    cp "$PROJECT_DIR/hooks/"* "$HOME/.config/aqua-voice-hook/hooks/" 2>/dev/null || true
    chmod +x "$HOME/.config/aqua-voice-hook/hooks/"* 2>/dev/null || true
    echo "  Copied example hooks"
fi

echo ""
echo "=== Done ==="
echo "  App:      $APP_DIR"
echo "  Config:   ~/.config/aqua-voice-hook/config.json"
echo "  Hooks:    ~/.config/aqua-voice-hook/hooks/"
echo "  Settings: open aqua-hook://settings"
echo ""
echo "  The app is now running. Dictate with Aqua Voice to test."
