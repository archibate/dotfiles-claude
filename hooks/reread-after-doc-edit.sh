#!/usr/bin/bash
# PostToolUse hook: remind to re-read doc files after editing them
# CLAUDE.md: "After updating any documentation file, re-read the entire file to catch
# stale content, numbering errors, contradictions, and duplication introduced by the edit."
set -euo pipefail

input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // .tool_input.file // ""')

# Skip if no file path
[ -n "$file_path" ] || exit 0

# Only fire for markdown files
case "$file_path" in
    *.md) ;;
    *) exit 0 ;;
esac

printf '📝 You just edited %s — re-read the entire file to catch stale content, numbering errors, contradictions, and duplication.\n' "$file_path" >&2
exit 2
