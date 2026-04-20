#!/usr/bin/bash
# PostToolUse hook: after editing a markdown or code file, inject a
# re-read reminder. See "Re-read After Edit" in CLAUDE.md.
set -euo pipefail

input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // .tool_input.file // ""')

# Skip if no file path
[ -n "$file_path" ] || exit 0

case "$file_path" in
    *.md|*.py|*.ts|*.js|*.tsx|*.jsx|*.c|*.cpp|*.h|*.hpp|*.rs|*.go|*.java|*.sh|*.toml|*.yaml|*.yml|*.json)
        printf 'Silently audit the edited region of %s (±30 lines). See "Re-read After Edit" in ~/.claude/CLAUDE.md.\n' "$file_path" >&2
        exit 2
        ;;
esac
