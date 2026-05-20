#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="Aqua Voice Hook"
BUNDLE_ID="com.aqua-voice-hook"
APP_DIR="/Applications/${APP_NAME}.app"
LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
LAUNCH_AGENT="$LAUNCH_AGENT_DIR/${BUNDLE_ID}.plist"

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
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BINARY" "$APP_DIR/Contents/MacOS/AquaVoiceHook"
cp "$PROJECT_DIR/Sources/AquaVoiceHook/Info.plist" "$APP_DIR/Contents/Info.plist"

echo "  Installed: $APP_DIR"

echo ""
echo "=== Installing LaunchAgent ==="
# Unload existing if present
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

# Copy example hooks if hooks dir is empty
if [[ -d "$PROJECT_DIR/hooks" ]] && [[ -z "$(ls -A "$HOME/.config/aqua-voice-hook/hooks" 2>/dev/null)" ]]; then
    cp "$PROJECT_DIR/hooks/"* "$HOME/.config/aqua-voice-hook/hooks/" 2>/dev/null || true
    chmod +x "$HOME/.config/aqua-voice-hook/hooks/"* 2>/dev/null || true
    echo "  Copied example hooks"
fi

echo ""
echo "=== Done ==="
echo "  App:     $APP_DIR"
echo "  Config:  ~/.config/aqua-voice-hook/config.json"
echo "  Hooks:   ~/.config/aqua-voice-hook/hooks/"
echo "  Settings: open aqua-hook://settings"
echo ""
echo "  The monitor is now running. Dictate with Aqua Voice to test."
