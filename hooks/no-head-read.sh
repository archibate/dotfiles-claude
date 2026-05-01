#!/usr/bin/bash
set -euo pipefail

source "$(dirname "$0")/lib/bypass.sh"
source "$(dirname "$0")/lib/emit.sh"
source "$(dirname "$0")/lib/read_input.sh"

read_bash_command
bypass_check BYPASS_HEAD_READ_CHECK

# Skip when sudo precedes head — Read runs without elevated privileges so
# cannot substitute for `sudo head -3 /etc/shadow`. Gap class excludes
# `;` / `&` / `|` so a stray earlier sudo doesn't silence the check.
if echo "$command" | grep -qP '\bsudo\s+[^;&|\n]*?\bhead\b'; then
    exit 0
fi

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
If this is a legitimate use, or a false-positive match (e.g. the pattern appears inside a string, comment, or filename, not as an executed command), add comment \`# BYPASS_HEAD_READ_CHECK\` before the first line of command."
fi

exit 0
