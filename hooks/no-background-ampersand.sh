#!/usr/bin/bash
set -euo pipefail

source "$(dirname "$0")/lib/bypass.sh"
source "$(dirname "$0")/lib/emit.sh"
source "$(dirname "$0")/lib/read_input.sh"

read_bash_command
bypass_check BYPASS_BACKGROUND_CHECK

# Check if any line ends with & (possibly with trailing whitespace)
# Match: command& or command & but not && (logical AND)
# Also catches multi-line commands where & appears at end of a line
if echo "$command" | grep -qE '[^&]&[[:space:]]*$'; then
    emit_pre_tool_deny 'Do not use & for background execution. Use the run_in_background parameter instead:
  Bash(command="...", run_in_background=true)
If this is a legitimate use, or a false-positive match (e.g. the pattern appears inside a string, comment, or filename, not as an executed command), add comment `# BYPASS_BACKGROUND_CHECK` before the first line of command.'
fi

exit 0
