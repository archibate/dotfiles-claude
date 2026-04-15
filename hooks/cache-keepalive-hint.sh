#!/usr/bin/bash
# PostToolUse hook: remind to load /cache-hygiene after launching background work
# CLAUDE.md: "After launching a background agent or task (run_in_background: true),
# load /cache-hygiene and follow its keep-alive protocol."
# Catches both explicit run_in_background and auto-backgrounded (timeout) tasks.
# Only fires once per session (flag file prevents repeats).
set -euo pipefail

input=$(cat)

# Detect background: explicit flag or auto-backgrounded via timeout
run_in_bg=$(echo "$input" | jq -r '.tool_input.run_in_background // false')
bg_id=$(echo "$input" | jq -r '.tool_response.backgroundTaskId // empty')

if [ "$run_in_bg" != "true" ] && [ -z "$bg_id" ]; then
    exit 0
fi

session_id=$(echo "$input" | jq -r '.session_id // "unknown"')
flag="/tmp/.claude-cache-hygiene-${session_id}"

if [ -f "$flag" ]; then
    exit 0
fi

touch "$flag"
printf '⏳ Background task launched — load /cache-hygiene and follow its keep-alive protocol to keep the 5-min prompt cache warm.\n' >&2
exit 2
