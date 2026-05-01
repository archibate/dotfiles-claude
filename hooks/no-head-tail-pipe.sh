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
    emit_pre_tool_deny 'Do not pipe into `| head` / `| tail` — they truncate by line position and discard the rest. The harness already saves large output to a file and shows a head preview, so plain `cmd` gives you the same visible head AND the rest for rg/Read.

Prefer the producer'"'"'s native limit (semantic — short-circuits work):
  rg / grep   →  -m N
  fd          →  --max-results N

If this is a legitimate use, or a false-positive match (e.g. the pattern appears inside a string, comment, or filename, not as an executed command), add comment `# BYPASS_HEAD_TAIL_CHECK` before the first line of command.'
fi

exit 0
