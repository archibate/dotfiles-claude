#!/usr/bin/bash
set -euo pipefail

input=$(cat)
command=$(jq -r '.tool_input.command // ""' <<< "$input")

# Skip if empty
if [ -z "$command" ]; then
    exit 0
fi

# Bypass marker
if echo "$command" | grep -qF 'BYPASS_DEVNULL_CHECK'; then
    exit 0
fi

# Detect any redirection to /dev/null:
#   >/dev/null, > /dev/null, >>/dev/null, 2>/dev/null, 2>>/dev/null,
#   &>/dev/null, &>>/dev/null
# The common denominator is `>` followed by optional whitespace then `/dev/null`.
if echo "$command" | grep -qP '>\s*/dev/null\b'; then
    source "$(dirname "$0")/lib/emit.sh"
    emit_pre_tool_deny 'Do not redirect to /dev/null — noise is cheaper than blindness.
Remove the `>/dev/null` / `2>/dev/null` so output reaches the agent.
If you must suppress output, add comment `BYPASS_DEVNULL_CHECK` to the first line of command.'
fi

exit 0
