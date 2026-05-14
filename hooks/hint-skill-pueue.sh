#!/usr/bin/bash
# PreToolUse hook: block pueue commands until the /pueue skill has been loaded.
# Denies once per session per compact, then allows through (one-shot guardrail).
set -euo pipefail

source "$(dirname "$0")/lib/emit.sh"
source "$(dirname "$0")/lib/session_lock.sh"
source "$(dirname "$0")/lib/anchors.sh"

input=$(cat)
command=$(jq -r '.tool_input.command // ""' <<< "$input")

if ! grep -qP "(${CMD_ANCHOR_SUDO}|${CMD_WRAPPER})pueue${CMD_TRAIL}" <<< "$command"; then
    exit 0
fi

SID=$(jq -r '.session_id // "unknown"' <<< "$input")
case "$SID" in agent-*) exit 0 ;; esac

SKILL_CACHE_DIR=/tmp/claude-pueue-skill-loaded
HINT_CACHE_DIR=/tmp/claude-pueue-skill-hint
SKILL_CACHE="$SKILL_CACHE_DIR/$SID"
HINT_CACHE="$HINT_CACHE_DIR/$SID"

mkdir -p "$SKILL_CACHE_DIR" "$HINT_CACHE_DIR"
reset_on_compact "$SID" "$SKILL_CACHE_DIR" "$SKILL_CACHE"
reset_on_compact "$SID" "$HINT_CACHE_DIR" "$HINT_CACHE"

[ -f "$SKILL_CACHE" ] && exit 0
[ -f "$HINT_CACHE" ] && exit 0

touch "$HINT_CACHE"
emit_pre_tool_deny "Load /pueue skill first — invoke Skill tool with skill='pueue' to get the standardised workflow and guardrails before running pueue commands. Ignore this hint if false positive trigger."
