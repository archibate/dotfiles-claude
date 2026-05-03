#!/usr/bin/bash
# PreToolUse hook: nudge the agent to load the `just-cli` skill before it
# runs `just <recipe>` in Bash or edits/writes a justfile. Fires at most once
# per session_id across all three trigger forms (so a session that runs `just
# build` and then edits the justfile only sees the hint once).
#
# Uses the shared anchor library to detect `just` at command position,
# including sudo and shell-evaluator wrappers (`bash -c "just build"`,
# `eval just deploy`). Substring uses like `cd /tmp/justice` or prose
# mentions inside echo/grep arguments do not trip it.
#
# Matcher registration (settings.json): Bash and Write|Edit|MultiEdit. The
# script routes on which input field is present.
set -euo pipefail

source "$(dirname "$0")/lib/emit.sh"
source "$(dirname "$0")/lib/anchors.sh"

input=$(cat)
command=$(jq -r '.tool_input.command // ""' <<< "$input")
file_path=$(jq -r '.tool_input.file_path // .tool_input.file // ""' <<< "$input")

triggered=0

if [ -n "$command" ] && \
   echo "$command" | grep -qP "(${CMD_ANCHOR_SUDO}|${CMD_WRAPPER})just${CMD_TRAIL}"; then
    triggered=1
fi

if [ -n "$file_path" ]; then
    base=$(basename "$file_path" | tr '[:upper:]' '[:lower:]')
    [ "$base" = "justfile" ] && triggered=1
fi

[ "$triggered" -eq 1 ] || exit 0

SID=$(jq -r '.session_id // "unknown"' <<< "$input")
CACHE_DIR=/tmp/claude-skill-hint-just-cli
CACHE="$CACHE_DIR/$SID"
mkdir -p "$CACHE_DIR"
[ -f "$CACHE" ] && exit 0
touch "$CACHE"

emit_pre_tool_warn 'About to invoke `just` or touch a justfile. Load the /just-cli skill via the Skill tool first — it documents recipe syntax, dependencies, and idioms that prevent silent justfile bugs. Skip if the call is a trivial `just --list` / `just --version`.'
