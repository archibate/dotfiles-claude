#!/usr/bin/bash
set -euo pipefail

source "$(dirname "$0")/lib/bypass.sh"
source "$(dirname "$0")/lib/emit.sh"
source "$(dirname "$0")/lib/read_input.sh"

read_bash_command
bypass_check BYPASS_HEAD_READ_CHECK

# Detect head with line count reading a file: head -N file, head -n N file, head --lines=N file
# Patterns: head -80, head -n 80, head --lines=80, head -n80
# Only match head at command position (start of line or after && ; |), not inside strings
if echo "$command" | grep -qP '(^|&&|;|\|)\s*head\s+(-\d+|-n\s*\d+|--lines[= ]\d+)\s+[^\s|;&>]+\s*$'; then

    # Extract line count
    limit=$(echo "$command" | grep -oP '\bhead\s+\K(-\d+|-n\s*\d+|--lines[= ]\d+)' | head -1 | grep -oP '\d+' || true)

    # Extract filename (the non-flag argument after head and its flags)
    file=$(echo "$command" | grep -oP '\bhead\s+(-\d+|-n\s*\d+|--lines[= ]\d+)\s+\K[^\s|;&>]+' | head -1 || true)

    if [ -n "$file" ] && [ -n "$limit" ]; then
        example=$(printf '  Read(file_path="%s", limit=%s)' "$file" "$limit")
    else
        example='  Read(file_path="<path>", limit=<num_lines>)'
    fi

    emit_pre_tool_deny "Use Read tool with limit instead of head for reading file lines.
${example}
If you have legitimate reason, add comment \`# BYPASS_HEAD_READ_CHECK\` before the first line of command."
fi

exit 0
