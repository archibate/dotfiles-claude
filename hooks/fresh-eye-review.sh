#!/usr/bin/bash
# Stop hook: remind to review changes with fresh eyes before stopping
# Fires once per batch of unreviewed edits, then enters cooldown.
# Cooldown is cleared by next user message (UserPromptSubmit hook).
set -euo pipefail

input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id // "unknown"')
state_dir="/tmp/.claude-hooks-${session_id}"

if [ ! -f "$state_dir/needs-review" ]; then
    exit 0
fi

rm -f "$state_dir/needs-review"
touch "$state_dir/review-cooldown"
echo '{"decision": "block", "reason": "Re-read changed files with fresh eyes, fix any issues found. Then rewrite your final response — the user only sees your last message (prior tool calls and responses are collapsed in the UI). If issues were found and fixed, include both a summary of the original work and what you fixed. If no issues, restate your original response so the user has full context. Maintain the same structure and formatting quality as your prior response."}'
exit 0
