#!/usr/bin/bash
# UserPromptSubmit hook: clear review cooldown so new edits trigger review again.
set -euo pipefail

input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id // "unknown"')
rm -f "/tmp/.claude-hooks-${session_id}/review-cooldown"
exit 0
