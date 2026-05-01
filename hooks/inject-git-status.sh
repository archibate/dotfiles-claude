#!/usr/bin/bash
# BYPASS_DEVNULL_CHECK
set -euo pipefail

# Read payload from stdin to extract session_id. Default to "unknown" if stdin
# is a TTY (manual run) or jq fails on non-JSON input.
PAYLOAD=""
if ! [ -t 0 ]; then
  PAYLOAD=$(cat || true)
fi
SID=$(printf '%s' "$PAYLOAD" | jq -r '.session_id // "unknown"' 2>/dev/null) || SID="unknown"
[ -z "$SID" ] && SID="unknown"

# Skip if not inside a git repo.
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

MAX_LINES=20
STATUS=$(git status -sb)
TOTAL=$(printf '%s\n' "$STATUS" | wc -l | tr -d ' ')

if [ "$TOTAL" -gt "$MAX_LINES" ]; then
  REMAINING=$((TOTAL - MAX_LINES))
  SHOWN=$(printf '%s\n' "$STATUS" | sed -n "1,${MAX_LINES}p")
  CTX="Git status (showing first ${MAX_LINES} of ${TOTAL} lines, ${REMAINING} more):
${SHOWN}"
else
  CTX="Git status:
${STATUS}"
fi

# Skip if identical to last emission for this session — most turns repeat the
# same status, so re-injecting it costs uncached input tokens for no signal.
CACHE_DIR=/tmp/claude-git-status
CACHE_FILE="${CACHE_DIR}/${SID}"
mkdir -p "$CACHE_DIR"
if [ -f "$CACHE_FILE" ] && [ "$(cat "$CACHE_FILE")" = "$CTX" ]; then
  exit 0
fi

# Persist atomically: temp file + rename, so a crashed hook never leaves a
# truncated cache that would mismatch and force a re-emit next turn.
TMP="${CACHE_FILE}.tmp.$$"
printf '%s' "$CTX" > "$TMP"
mv "$TMP" "$CACHE_FILE"

jq -n --arg ctx "$CTX" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $ctx
  }
}'
