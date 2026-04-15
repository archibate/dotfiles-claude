#!/usr/bin/bash
# PostToolUse hook: mark that files were modified and need review
# Skips if in post-review cooldown (agent is making review-fixup edits).
set -euo pipefail

input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id // "unknown"')
state_dir="/tmp/.claude-hooks-${session_id}"
mkdir -p "$state_dir"

# Don't re-set flag during review cooldown
if [ -f "$state_dir/review-cooldown" ]; then
    exit 0
fi

touch "$state_dir/needs-review"
exit 0
