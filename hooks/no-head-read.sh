#!/usr/bin/bash
set -euo pipefail

input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // ""')

# Skip if empty
if [ -z "$command" ]; then
    exit 0
fi

# Bypass marker
if echo "$command" | grep -qF 'BYPASS_HEAD_READ_CHECK'; then
    exit 0
fi

# Detect head with line count reading a file: head -N file, head -n N file, head --lines=N file
# Patterns: head -80, head -n 80, head --lines=80, head -n80
# Only match head at command position (start of line or after && ; ||), not inside strings
if echo "$command" | grep -qP '(^|&&|;|\|\|)\s*head\s+(-\d+|-n\s*\d+|--lines[= ]\d+)\s+[^\s|;&>]'; then

    # Extract line count
    limit=$(echo "$command" | grep -oP '\bhead\s+\K(-\d+|-n\s*\d+|--lines[= ]\d+)' | head -1 | grep -oP '\d+' || true)

    # Extract filename (the non-flag argument after head and its flags)
    file=$(echo "$command" | grep -oP '\bhead\s+(-\d+|-n\s*\d+|--lines[= ]\d+)\s+\K[^\s|;&>]+' | head -1 || true)

    printf 'Use Read tool with limit instead of head for reading file lines.\n' >&2
    if [ -n "$file" ] && [ -n "$limit" ]; then
        printf '  Read(file_path="%s", limit=%s)\n' "$file" "$limit" >&2
    else
        printf '  Read(file_path="<path>", limit=<num_lines>)\n' >&2
    fi
    printf 'If you must use head, add comment `BYPASS_HEAD_READ_CHECK` to the first line of command.\n' >&2
    exit 2
fi

exit 0
