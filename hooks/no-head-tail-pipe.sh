#!/usr/bin/bash
# PreToolUse hook: nudge once per session when a Bash command pipes its
# trailing stage into `head` / `tail`. Soft advisory, not a block — the user
# may have a legitimate reason, and the harness already saves full output, so
# truncation only costs the agent visibility (recoverable next call) rather
# than corrupting state. One hint per session is enough; after that the agent
# has been reminded and silently allowing repeats avoids hint-spam.
set -euo pipefail

source "$(dirname "$0")/lib/emit.sh"
source "$(dirname "$0")/lib/read_input.sh"

read_bash_command

# Detect trailing `| head` / `| tail` — the last pipeline stage.
# `(^|[^|])\|` requires a single `|` (not `||`), so `cmd || head ...` is left alone.
# `[^|]*$` anchors head/tail as trailing — intermediate uses like `cmd | head | wc`
# intentionally pass through.
echo "$command" | grep -qP '(^|[^|])\|\s*(head|tail)\b[^|]*$' || exit 0

SID=$(jq -r '.session_id // "unknown"' <<< "$input")
CACHE_DIR=/tmp/claude-hint-no-head-tail-pipe
CACHE="$CACHE_DIR/$SID"
mkdir -p "$CACHE_DIR"
[ -f "$CACHE" ] && exit 0
touch "$CACHE"

emit_pre_tool_warn 'Trailing `| head` / `| tail` truncates by line position and discards the rest (irrecoverable if the producer was expensive or non-idempotent: the pipe truncation happens before the harness sees the output). The harness already saves large output to a file and shows a head preview, so plain `cmd` gives you the same visible head AND the rest for rg/Read.

Prefer the producer'"'"'s native limit (semantic — short-circuits work):
  rg / grep   →  -m N
  fd          →  --max-results N
  git log     →  -n N

(One-shot hint — will not fire again this session.)'
