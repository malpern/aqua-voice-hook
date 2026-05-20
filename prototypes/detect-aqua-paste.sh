#!/bin/bash
# Lightweight test: detect clipboard changes that Aqua Voice makes when it
# pastes transcribed text. Aqua Voice uses Cmd+V (paste) to insert text,
# which means the clipboard changes right before the paste event.
#
# Run this, then dictate something with Aqua Voice and watch the output.
# Press Ctrl+C to stop.

echo "=== Aqua Voice Paste Detector ==="
echo "Monitoring clipboard for changes..."
echo "Dictate something with Aqua Voice and watch for detections."
echo "Press Ctrl+C to stop."
echo ""

LAST_CLIPBOARD=""
LAST_CHANGE_COUNT=$(pbpaste 2>/dev/null | md5)

while true; do
    CURRENT=$(pbpaste 2>/dev/null)
    CURRENT_HASH=$(echo "$CURRENT" | md5)

    if [[ "$CURRENT_HASH" != "$LAST_CHANGE_COUNT" ]]; then
        TIMESTAMP=$(date '+%H:%M:%S.%3N')
        FRONTMOST=$(osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null)
        CHAR_COUNT=${#CURRENT}

        echo "[$TIMESTAMP] CLIPBOARD CHANGED"
        echo "  Frontmost app: $FRONTMOST"
        echo "  Length: $CHAR_COUNT chars"
        echo "  Content: ${CURRENT:0:200}"
        echo ""

        LAST_CHANGE_COUNT="$CURRENT_HASH"
    fi

    sleep 0.1
done
