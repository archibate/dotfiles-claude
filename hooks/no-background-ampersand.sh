#!/usr/bin/bash
set -euo pipefail

input=$(cat)
command=$(jq -r '.tool_input.command // ""' <<< "$input")

# Explicit bypass marker
if echo "$command" | grep -qF 'BYPASS_BACKGROUND_CHECK'; then
    exit 0
fi

# Check if any line ends with & (possibly with trailing whitespace)
# Match: command& or command & but not && (logical AND)
# Also catches multi-line commands where & appears at end of a line
if echo "$command" | grep -qE '[^&]&[[:space:]]*$'; then
    source "$(dirname "$0")/lib/emit.sh"
    emit_pre_tool_deny 'Do not use & for background execution. Use the run_in_background parameter instead:
  Bash(command="...", run_in_background=true)
If you must use &, add comment `BYPASS_BACKGROUND_CHECK` to the first line of command.'
fi

exit 0
