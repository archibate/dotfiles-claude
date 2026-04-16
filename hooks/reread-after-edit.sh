#!/usr/bin/bash
# PostToolUse hook: remind to re-read files after editing them
# - Markdown: re-read full file (stale content, contradictions, style)
# - Code: re-read nearby context only (style consistency, not full file — too expensive)
set -euo pipefail

input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // .tool_input.file // ""')

# Skip if no file path
[ -n "$file_path" ] || exit 0

case "$file_path" in
    *.md)
        printf 'Re-read %s in full to catch: stale content, contradictions, duplication, and style consistency (does the new text match the tone/formatting/conventions of surrounding content?).\n' "$file_path" >&2
        exit 2
        ;;
    *.py|*.ts|*.js|*.tsx|*.jsx|*.c|*.cpp|*.h|*.hpp|*.rs|*.go|*.java|*.sh|*.toml|*.yaml|*.yml|*.json)
        printf 'Re-read the edited region of %s (±30 lines around the edit) to check: does the new code match surrounding style conventions (naming, patterns, idioms)?\n' "$file_path" >&2
        exit 2
        ;;
esac
