#!/bin/zsh
# Example hook: log every Aqua Voice dictation to a file.
# The transcribed text comes as $1 and via env vars.

TEXT="$1"
LOG_FILE="$HOME/.aqua-voice-log.jsonl"

echo "{\"timestamp\": \"$AQUA_TIMESTAMP\", \"app\": \"$AQUA_FRONTMOST_APP\", \"text\": \"$TEXT\"}" >> "$LOG_FILE"

echo "Logged to $LOG_FILE"
