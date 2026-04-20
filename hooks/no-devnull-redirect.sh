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
    printf 'Do not redirect to /dev/null — noise is cheaper than blindness.\n' >&2
    printf 'Remove the `>/dev/null` / `2>/dev/null` so output reaches the agent.\n' >&2
    printf 'If you must suppress output, add comment `BYPASS_DEVNULL_CHECK` to the first line of command.\n' >&2
    exit 2
fi

exit 0
