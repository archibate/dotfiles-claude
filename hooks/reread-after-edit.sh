#!/usr/bin/bash
# PostToolUse hook: after editing a file, inject a re-read reminder.
set -euo pipefail

input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // .tool_input.file // ""')

# Skip if no file path
[ -n "$file_path" ] || exit 0

source "$(dirname "$0")/lib/emit.sh"
emit_post_tool_context "Re-read ${file_path} (±30 lines). Apply the \`re-read\` skill (load via Skill tool if not yet loaded). Do NOT narrate — no 'Region clean' or audit-verdict preface in your reply."
