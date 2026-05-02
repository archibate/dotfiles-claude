#!/usr/bin/bash
set -euo pipefail

# Surface peer Claude Code sessions in the same repo so the user notices
# potential edit collisions before issuing a prompt. Silent when no peers match.
#
# Test overrides (set by hooks/tests/run.sh):
#   PEER_ACTIVITY_TEST_SELF_ADDR   skip $TMUX_PANE / tmux display-message
#   PEER_ACTIVITY_TEST_SELF_ROOT   skip git rev-parse
#   PEER_ACTIVITY_TEST_PANES       skip tmux list-panes; use this verbatim

if [ -n "${PEER_ACTIVITY_TEST_SELF_ADDR:-}" ]; then
  SELF_ADDR="$PEER_ACTIVITY_TEST_SELF_ADDR"
else
  [ -n "${TMUX_PANE:-}" ] || exit 0
  command -v tmux >/dev/null 2>&1 || exit 0
  SELF_ADDR=$(tmux display-message -p -t "$TMUX_PANE" '#{session_name}:#{window_index}.#{pane_index}' 2>/dev/null) || exit 0
fi

# Repo root for scope filter. Without a git root we'd accidentally match every
# pane sharing $HOME, so fall back to exact-cwd matching in that case.
if [ -n "${PEER_ACTIVITY_TEST_SELF_ROOT:-}" ]; then
  SELF_ROOT="$PEER_ACTIVITY_TEST_SELF_ROOT"
  MATCH_MODE=prefix
elif SELF_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) && [ -n "$SELF_ROOT" ]; then
  MATCH_MODE=prefix
else
  SELF_ROOT=$(pwd -P)
  MATCH_MODE=exact
fi

if [ -n "${PEER_ACTIVITY_TEST_PANES:-}" ]; then
  PANES="$PEER_ACTIVITY_TEST_PANES"
else
  PANES=$(tmux list-panes -a -F '#{pane_current_command}	#{session_name}:#{window_index}.#{pane_index}	#{pane_current_path}	#{pane_title}' 2>/dev/null) || exit 0
fi

PEERS=$(printf '%s\n' "$PANES" | awk -F'\t' \
  -v self="$SELF_ADDR" -v root="$SELF_ROOT" -v mode="$MATCH_MODE" '
  $1 != "claude" { next }
  $2 == self    { next }
  {
    in_scope = ($3 == root)
    if (!in_scope && mode == "prefix" && index($3, root "/") == 1) in_scope = 1
    if (!in_scope) next
  }
  $4 == ""    { next }
  $4 ~ /^✳/  { next }   # idle — no collision risk
  {
    title = $4
    sub(/^[^ ]+[ ]+/, "", title)
    printf "  🔵 %s — %s\n", $2, title
  }
')

[ -n "$PEERS" ] || exit 0

CTX="Other Claude sessions active in this repo:
${PEERS}"

jq -n --arg ctx "$CTX" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $ctx
  }
}'
