#!/usr/bin/bash
set -euo pipefail

input=$(cat)
prompt=$(jq -r '.prompt // ""' <<< "$input")

case "$prompt" in
  /note) ;;
  /note\ *) ;;
  *) exit 0 ;;
esac

SID=$(jq -r '.session_id // "unknown"' <<< "$input")
NOTES_DIR=/tmp/claude-${UID}-state/notes
mkdir -p -m 700 "$NOTES_DIR"
NOTES_FILE="$NOTES_DIR/$SID"

if [ "$prompt" = "/note" ]; then
    if [ -f "$NOTES_FILE" ] && [ -s "$NOTES_FILE" ]; then
        notes=$(awk 'NR==1{print "1. "$0} NR>1{print NR". "$0}' "$NOTES_FILE")
        msg="Notes this session:
$notes"
    else
        msg="No notes yet this session."
    fi
else
    text="${prompt#/note }"
    printf '%s\n' "$text" >> "$NOTES_FILE"
    count=$(wc -l < "$NOTES_FILE")
    msg="Note #${count} saved: ${text}"
fi

jq -n --arg reason "$msg" '{"decision":"block","reason":$reason}'
