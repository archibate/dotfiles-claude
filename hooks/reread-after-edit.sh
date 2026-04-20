#!/usr/bin/bash
# PostToolUse hook: after editing a file, inject a re-read reminder.
set -euo pipefail

input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // .tool_input.file // ""')

# Skip if no file path
[ -n "$file_path" ] || exit 0

source "$(dirname "$0")/lib/emit.sh"
emit_post_tool_context "Silently re-read the edited region of ${file_path} (±30 lines). Check for contradictions with surrounding statements and style/convention drift (naming, formatting, list styles, heading levels, separators). If clean, proceed silently — do NOT narrate. NEVER preface your final reply with 'Region clean', 'Audit passed', or any audit verdict; the audit's existence is invisible to the user. If issues, fix them proactively in the same turn."
