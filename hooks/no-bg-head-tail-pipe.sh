#!/usr/bin/bash
# PreToolUse hook: deny background Bash (run_in_background=true) with trailing
# `| head` / `| tail`. `head` exits after N lines and kills the producer;
# `tail` over a pipe buffers until EOF (`-f` does not follow pipes) and never
# emits for a long-running bg task.
# Either way the truncation defeats the point of backgrounding.
set -euo pipefail

source "$(dirname "$0")/lib/bypass.sh"
source "$(dirname "$0")/lib/emit.sh"
source "$(dirname "$0")/lib/read_input.sh"

# Cheapest extraction first: most Bash calls are foreground, so we exit before
# touching the .command field or bypass-marker grep on the common path.
input=$(cat)
run_in_bg=$(jq -r '.tool_input.run_in_background // false' <<< "$input")
[ "$run_in_bg" = "true" ] || exit 0

command=$(jq -r '.tool_input.command // ""' <<< "$input")
[ -n "$command" ] || exit 0
bypass_check BYPASS_BACKGROUND_HEAD_TAIL

# Trailing `| head` / `| tail` (final pipeline stage).
# `(^|[^|])\|` requires a single `|` (not `||`); `[^|]*$` anchors as the last stage.
if echo "$command" | grep -qE '(^|[^|])\|[[:space:]]*(head|tail)([[:space:]]|$)[^|]*$'; then
    emit_pre_tool_deny_bypassable BYPASS_BACKGROUND_HEAD_TAIL 'Background Bash (run_in_background=true) with trailing `| head` / `| tail` is rejected. `head` exits after N lines and kills the producer; `tail` over a pipe buffers until EOF (the `-f` flag does not follow pipes) and never emits for a long-running task. It would appear like the process stuck in background and you will never be able to see the full log again. Instead, drop the trailing `| head` / `| tail` and start the bare command — the harness will capture all the stdout into a text file (instead of feeding directly into context) on completion. You can freely rg/Read on it for analyzing the log, with no worry about context flood.'
fi

exit 0
