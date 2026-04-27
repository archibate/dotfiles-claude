#!/usr/bin/bash
set -euo pipefail

source "$(dirname "$0")/lib/bypass.sh"
source "$(dirname "$0")/lib/emit.sh"
source "$(dirname "$0")/lib/read_input.sh"

read_bash_command
bypass_check BYPASS_HEAD_TAIL_CHECK

# Detect trailing `| head` / `| tail` — the last pipeline stage.
# `(^|[^|])\|` requires a single `|` (not `||`), so `cmd || head ...` is left alone.
# `[^|]*$` anchors head/tail as trailing — intermediate uses like `cmd | head | wc`
# intentionally pass through.
if echo "$command" | grep -qP '(^|[^|])\|\s*(head|tail)\b[^|]*$'; then
    emit_pre_tool_deny 'Do not pipe into `| head` / `| tail` — they truncate by position and hide output the agent may need. If the prior stage is expensive or non-idempotent you have also lost the rest of its output.
Run the command without the truncation; the harness micro-compacts large output automatically.
If you believe this is a false positive, add comment `BYPASS_HEAD_TAIL_CHECK` to the first line of command.'
fi

exit 0
