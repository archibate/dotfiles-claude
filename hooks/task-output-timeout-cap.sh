#!/usr/bin/bash
# PreToolUse hook: cap TaskOutput timeout at 240s to prevent cache busting.
# A blocking call >4 min risks exceeding the 5-min prompt cache TTL.
set -euo pipefail

input=$(cat)
timeout=$(jq -r '.tool_input.timeout // 30000' <<< "$input")

if [ "$timeout" -gt 240000 ] 2>/dev/null; then
    printf 'TaskOutput timeout %sms exceeds 240s cache-safe cap. Use timeout ≤ 240000, or block=false for a non-blocking peek.\n' "$timeout" >&2
    exit 2
fi

exit 0
