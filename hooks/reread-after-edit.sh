#!/usr/bin/bash
# PostToolUse hook: after editing a file, inject a re-read reminder.
set -euo pipefail

source "$(dirname "$0")/lib/emit.sh"
source "$(dirname "$0")/lib/read_input.sh"

read_file_path
emit_post_tool_context "Re-read ${file_path} (±30 lines) using the Read tool. Audit surrounding context consistency using the /re-read skill (load it once). Do NOT narrate — no 'Region clean' or audit-verdict preface in your reply."
