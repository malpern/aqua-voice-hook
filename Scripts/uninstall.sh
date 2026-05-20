#!/bin/zsh
set -euo pipefail

BUNDLE_ID="com.aqua-voice-hook"
APP_DIR="/Applications/Aqua Voice Hook.app"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/${BUNDLE_ID}.plist"

echo "=== Uninstalling Aqua Voice Hook ==="

launchctl bootout "gui/$(id -u)/$BUNDLE_ID" 2>/dev/null && echo "  Stopped LaunchAgent" || echo "  LaunchAgent not running"
rm -f "$LAUNCH_AGENT" && echo "  Removed LaunchAgent plist"
rm -rf "$APP_DIR" && echo "  Removed app bundle"

echo ""
echo "  Config preserved at: ~/.config/aqua-voice-hook/"
echo "  To remove config too: rm -rf ~/.config/aqua-voice-hook"
