#!/usr/bin/bash
set -euo pipefail

source "$(dirname "$0")/lib/bypass.sh"
source "$(dirname "$0")/lib/emit.sh"
source "$(dirname "$0")/lib/read_input.sh"

read_bash_command
bypass_check BYPASS_SED_PRINT_CHECK

# Detect sed -n with numeric line printing on a file (e.g., sed -n '12,13p' file)
# Pattern: sed -n followed by a number or number range ending in p, then a filename
# We want to catch: '12p', "12p", 12p, '12,13p', "12,13!p", etc.
# We do NOT want to catch: 's/foo/bar/p' (substitution), '/pattern/p' (regex)
# Only match sed at command position (start of line or after && ; |), not inside strings
if echo "$command" | grep -qP '(^|&&|;|\|)\s*sed\s+-n\s+['"'"'"]?\d+[,.!]\d*p['"'"'"]?\s+[^\s|;&>]+\s*$' ||
   echo "$command" | grep -qP '(^|&&|;|\|)\s*sed\s+-n\s+['"'"'"]?\d+p['"'"'"]?\s+[^\s|;&>]+\s*$'; then

    # Extract the line numbers for helpful suggestion
    range=$(echo "$command" | grep -oP '\bsed\s+-n\s+\K['"'"'"]?\d+(?:[,.!]\d+)?p['"'"'"]?' | head -1 | tr -d "'\"" || true)
    file=$(echo "$command" | grep -oP '\bsed\s+-n\s+['"'"'"]?\d+(?:[,.!]\d+)?p['"'"'"]?\s+\K\S+' | head -1 || true)

    # Parse range to calculate offset/limit (1-indexed to 0-indexed offset)
    offset=""
    limit=""
    if [ -n "$range" ]; then
        # Single line: 12p -> offset=11, limit=1
        if echo "$range" | grep -qP '^\d+p$'; then
            line_num=$(echo "$range" | grep -oP '^\d+')
            offset=$((line_num - 1))
            limit=1
        # Range: 12,13p -> offset=11, limit=2
        elif echo "$range" | grep -qP '^\d+,\d+p$'; then
            start=$(echo "$range" | grep -oP '^\d+')
            end=$(echo "$range" | grep -oP ',\d+' | tr -d ',')
            offset=$((start - 1))
            limit=$((end - start + 1))
        fi
    fi

    if [ -n "$file" ] && [ -n "$offset" ] && [ -n "$limit" ]; then
        example=$(printf '  Read(file_path="%s", offset=%d, limit=%d)' "$file" "$offset" "$limit")
    else
        example='  Read(file_path="<path>", offset=<start_line-1>, limit=<num_lines>)'
    fi

    emit_pre_tool_deny "Use Read tool with offset and limit instead of sed -n for reading specific lines.
${example}
If you believe this is a false positive, add comment \`BYPASS_SED_PRINT_CHECK\` to the first line of command."
fi

exit 0
