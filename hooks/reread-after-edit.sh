#!/usr/bin/bash
# PostToolUse hook: after editing a file, inject a re-read reminder.
# See "Re-read After Edit" in CLAUDE.md.
set -euo pipefail

input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // .tool_input.file // ""')

# Skip if no file path
[ -n "$file_path" ] || exit 0

source "$(dirname "$0")/lib/emit.sh"
emit_post_tool_context "Silently re-read the edited region of ${file_path} (±30 lines) to audit. See \"Re-read After Edit\" in ~/.claude/CLAUDE.md."
