#!/usr/bin/bash
set -euo pipefail

max_lines=80

input=$(cat)
command=$(jq -r '.tool_input.command // ""' <<< "$input")

# Detect heredoc (<<, not <<<)
has_heredoc=false
if echo "$command" | grep -qE '<<[^<]'; then
    has_heredoc=true
fi

# Detect inline -c script (multi-line string after -c flag)
# Patterns: python3 -c "...", bash -c '...', uv run python -c "..."
has_inline_c=false
inline_c_lines=0
if echo "$command" | grep -qE -- '-c\s+["'"'"']'; then
    # Extract content after -c and count lines
    # Use awk to find -c followed by quote and extract until matching quote
    inline_c_lines=$(printf '%s' "$command" | awk '
        BEGIN { in_c = 0; quote = ""; content = "" }
        /-c/ && !in_c {
            # Find the quote character after -c
            match($0, /-c[[:space:]]+(["'"'"'])/, arr)
            if (RSTART > 0) {
                quote = arr[1]
                in_c = 1
                # Get content starting from after the quote
                rest = substr($0, RSTART + RLENGTH)
                content = rest
            }
        }
        in_c && NR > 1 {
            content = content "\n" $0
        }
        END {
            # Count newlines in content
            gsub(/[^\n]/, "", content)
            print length(content) + 1
        }
    ')
    inline_c_lines=${inline_c_lines:-0}
    if [ "$inline_c_lines" -gt "$max_lines" ]; then
        has_inline_c=true
    fi
fi

# Exit if neither heredoc nor inline -c detected
if ! $has_heredoc && ! $has_inline_c; then
    exit 0
fi

# Bypass for git commit (heredoc used for commit message)
if echo "$command" | grep -qE '\bgit\s+commit\b'; then
    exit 0
fi

# Explicit bypass marker
if echo "$command" | grep -qF 'BYPASS_HEREDOC_RESTRICTION'; then
    exit 0
fi

# Count lines inside heredoc; allow if <= $max_lines
script_lines=0
detection_type=""
if $has_heredoc; then
    marker=$(printf '%s' "$command" | grep -oE "<<[-'\" ]*[A-Za-z_][A-Za-z0-9_]*" | head -1 | grep -oE '[A-Za-z_][A-Za-z0-9_]*$')
    if [ -n "$marker" ]; then
        script_lines=$(printf '%s' "$command" | awk -v m="$marker" '
            found && $0 == m { found=0; next }
            found { count++ }
            !found && index($0, "<<") && index($0, m) { found=1 }
            END { print count+0 }
        ')
        detection_type="Heredoc"
    fi
elif $has_inline_c; then
    script_lines=$inline_c_lines
    detection_type="Inline -c script"
fi

script_lines=${script_lines:-0}
if [ "$script_lines" -le "$max_lines" ]; then
    exit 0
fi

# Detect interpreter — order matters: uv run before python
if echo "$command" | grep -qE '\buv\s+run\b'; then
    interpreter="uv run"
    ext="py"
elif echo "$command" | grep -qE '\bpython3?\b'; then
    interpreter="python3"
    ext="py"
elif echo "$command" | grep -qE '\b(bash|sh)\b'; then
    interpreter="bash"
    ext="sh"
else
    # No relevant interpreter — allow
    exit 0
fi

# Determine temp dir
if [ -d "${CLAUDE_PROJECT_DIR:-}/temp" ]; then
    tmp_dir="${CLAUDE_PROJECT_DIR}/temp"
else
    tmp_dir="/tmp"
fi

tmp_file="${tmp_dir}/script_$$.${ext}"

case "$interpreter" in
    "uv run")
        example="Write(\"${tmp_file}\", <script>)  →  Bash(\"uv run ${tmp_file}\")"
        ;;
    "python3")
        example="Write(\"${tmp_file}\", <script>)  →  Bash(\"python3 ${tmp_file}\")"
        ;;
    "bash")
        example="Write(\"${tmp_file}\", <script>)  →  Bash(\"bash ${tmp_file}\")"
        ;;
esac

printf '%s >%s lines detected for %s. Use Write tool + temp file instead:\n  %s\nIf you must use inline script, add comment `BYPASS_INLINE_SCRIPT_RESTRICTION` to the first line of command.\n' \
    "$detection_type" "$max_lines" "$interpreter" "$example" >&2

exit 2
