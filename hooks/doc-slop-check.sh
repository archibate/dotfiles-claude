#!/usr/bin/bash
# PostToolUse hook: detect AI slop patterns in doc edits (over-bold, alarm language, etc.)
# Separate from reread hook — this focuses on writing style quality.
set -euo pipefail

input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // .tool_input.file // ""')

# Skip if no file path
[ -n "$file_path" ] || exit 0

# Only check markdown files
case "$file_path" in
    *.md) ;;
    *) exit 0 ;;
esac

new_string=$(echo "$input" | jq -r '.tool_input.new_string // .tool_input.content // ""')
[ -n "$new_string" ] || exit 0

warnings=""

# --- Bold density ---
# Strip label-style bolds first: "- **Label** —" or "- **Label** :" patterns are structural, not emphasis
emphasis_text=$(echo "$new_string" | sed -E 's/^[[:space:]]*-[[:space:]]+\*\*[^*]+\*\*[[:space:]]*(—|:)//g')
bold_count=$(echo "$emphasis_text" | grep -oP '\*\*' | wc -l || true)
bold_phrases=$((bold_count / 2))
line_count=$(echo "$new_string" | wc -l)
line_count=$((line_count > 0 ? line_count : 1))

if [ "$bold_phrases" -ge 2 ] && [ $((bold_phrases * 3)) -gt "$line_count" ]; then
    warnings="${warnings}  - bold density: ${bold_phrases} bold phrases in ${line_count} lines\n"
fi

# --- Alarm-word bold: **Important:**, **Note:**, **Warning:**, **CRITICAL**, etc. ---
alarm_matches=$(echo "$new_string" | grep -oiP '\*\*(Important|Note|Warning|Critical|Caution|Danger|MUST|NEVER)\s*:?\*\*' || true)
if [ -n "$alarm_matches" ]; then
    warnings="${warnings}  - alarm-word bold: $(echo "$alarm_matches" | tr '\n' ', ' | sed 's/, $//')\n"
fi

# --- ALL-CAPS words (4+ letter uppercase words, excluding known acronyms/env vars) ---
# Strip backtick-quoted spans first (code references like `BASH_MAX_TIMEOUT_MS` are not emphasis)
caps_text=$(echo "$new_string" | sed 's/`[^`]*`//g')
caps_runs=$(echo "$caps_text" | grep -oP '\b[A-Z]{4,}\b' | grep -vP '^(API|SDK|CLI|URL|JSON|HTML|CSS|HTTP|HTTPS|NDJSON|EOF|UUID|GLSL|REPL|CORS|OWASP|CRUD|CLAUDE|PYTHONUNBUFFERED|BYPASS)$' || true)
if [ -n "$caps_runs" ]; then
    caps_list=$(echo "$caps_runs" | head -5 | tr '\n' ', ' | sed 's/, $//')
    warnings="${warnings}  - ALL-CAPS words: ${caps_list}\n"
fi

if [ -z "$warnings" ]; then
    exit 0
fi

printf '⚠️ Doc edit AI slop patterns detected in %s:\n' "$file_path" >&2
printf '%b' "$warnings" >&2
printf 'Edits should blend into existing doc style. Review and tone down if these stand out. Ignore if emphasis was intentional.\n' >&2
exit 2
