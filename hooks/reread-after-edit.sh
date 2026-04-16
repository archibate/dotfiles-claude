#!/usr/bin/bash
# PostToolUse hook: remind to re-read files after editing them
# - Markdown: re-read ±30 lines (contradictions, style, structural consistency)
# - Code: re-read ±30 lines (style conventions, naming, patterns)
set -euo pipefail

input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // .tool_input.file // ""')

# Skip if no file path
[ -n "$file_path" ] || exit 0

case "$file_path" in
    *.md)
        printf 'Re-read the edited region of %s (±30 lines around the edit) to check: contradictions with nearby content, style consistency (tone/formatting), and structural consistency (separators, heading levels, list styles match surrounding sections).\n' "$file_path" >&2
        exit 2
        ;;
    *.py|*.ts|*.js|*.tsx|*.jsx|*.c|*.cpp|*.h|*.hpp|*.rs|*.go|*.java|*.sh|*.toml|*.yaml|*.yml|*.json)
        printf 'Re-read the edited region of %s (±30 lines around the edit) to check: does the new code match surrounding style conventions (naming, patterns, idioms)?\n' "$file_path" >&2
        exit 2
        ;;
esac
