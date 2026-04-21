#!/usr/bin/bash
set -euo pipefail

source "$(dirname "$0")/lib/bypass.sh"
source "$(dirname "$0")/lib/emit.sh"
source "$(dirname "$0")/lib/read_input.sh"

read_bash_command
bypass_check BYPASS_DEVNULL_CHECK

# Detect any redirection to /dev/null:
#   >/dev/null, > /dev/null, >>/dev/null, 2>/dev/null, 2>>/dev/null,
#   &>/dev/null, &>>/dev/null
# The common denominator is `>` followed by optional whitespace then `/dev/null`.
if echo "$command" | grep -qP '>\s*/dev/null\b'; then
    emit_pre_tool_deny 'Do not redirect to /dev/null — noise is cheaper than blindness.
Remove the `>/dev/null` / `2>/dev/null` so output reaches the agent.
If you believe this is a false positive, add comment `BYPASS_DEVNULL_CHECK` to the first line of command.'
fi

exit 0
