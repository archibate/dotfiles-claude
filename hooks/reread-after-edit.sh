#!/usr/bin/bash
# PostToolUse hook: after editing a file, inject a re-read reminder with inline checklist.
set -euo pipefail

source "$(dirname "$0")/lib/emit.sh"
source "$(dirname "$0")/lib/read_input.sh"

read_file_path
emit_post_tool_context "Re-read ${file_path} (±30 lines) and walk explicitly through each item:
- Over-emphasis: bold/emoji/🆕/ALL-CAPS density vs surrounding lines?
- Tonal drift in new content: matches sibling rhetorical strength and length?
- Justifying asides: parentheticals defending obvious claims?
- Hallucinated refs: uncommon API/flag/symbol verified against source or docs?
- Style drift: list/heading/separator/naming conventions consistent?
- Patch over restructure: bigger regroup needed instead of minimal-diff append?
- Module placement: new code/section in the right file/section?
- Comment/code mismatch: docstring still describes the behavior?
Silent fix per item. Do NOT narrate — no 'Region clean' or audit-verdict preface."
