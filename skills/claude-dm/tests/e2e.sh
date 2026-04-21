#!/usr/bin/env bash
# Live integration test for claude-dm against a disposable Claude session.
# Spawns claude on an isolated tmux socket and exercises every code path that
# depends on the peer being a real Claude process (state classification,
# transcript tail, sentinel matching, esc interrupt). Requires tmux, jq, awk,
# and the claude CLI with OAuth already configured. Costs one session init
# plus ~2 short prompt responses.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAUDE_DM="$HERE/bin/claude-dm"

SOCK=${CLAUDE_DM_E2E_SOCKET:-/tmp/claude-dm-e2e.sock}
export CLAUDE_DM_SOCKET=$SOCK

cleanup() {
  tmux -S "$SOCK" kill-server 2>&1 | head -1 || true
}
trap cleanup EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'OK:   %s\n' "$*"; }

state_of() {
  "$CLAUDE_DM" status "$1" 2>&1 | awk '/^state/{print $2}'
}

wait_state() {
  local target="$1" want="$2" timeout="${3:-60}" _
  for _ in $(seq "$timeout"); do
    [[ "$(state_of "$target")" == "$want" ]] && return 0
    sleep 1
  done
  return 1
}

echo "=== setup: claude on $SOCK ==="
cleanup
tmux -S "$SOCK" -f /dev/null new-session -d -s t -n c \
  'claude --thinking-display summarized'
wait_state t:0.0 idle 60 || fail "claude did not reach idle within 60s"
pass "claude reached idle"

echo "=== list shows target ==="
"$CLAUDE_DM" list | grep -q '^t:0.0' || fail "list missing t:0.0"
pass "list"

echo "=== status reports safe_to_dm=yes ==="
"$CLAUDE_DM" status t:0.0 | grep -qE '^safe_to_dm[[:space:]]+yes' \
  || fail "status not safe"
pass "status / safety gate"

echo "=== ask returns trimmed reply (no sentinel leak) ==="
reply=$("$CLAUDE_DM" ask t:0.0 \
  "Reply with exactly the single word PONG on its own line, nothing else." 90)
reply_clean=$(tr -d '[:space:]' <<<"$reply")
[[ "$reply_clean" == PONG ]] || fail "expected PONG, got '$reply'"
grep -qF 'DONE-' <<<"$reply" && fail "sentinel leaked into reply: '$reply'"
pass "ask / sentinel trim"

echo "=== esc interrupts a busy peer ==="
wait_state t:0.0 idle 30 || fail "not idle before esc"
"$CLAUDE_DM" send t:0.0 "Count slowly from 1 to 100, one number per line, pausing a second between."
wait_state t:0.0 busy 10 || fail "peer did not go busy after send"
"$CLAUDE_DM" esc t:0.0
sleep 3
st=$(state_of t:0.0)
[[ "$st" != busy ]] || fail "esc did not interrupt; state still busy"
pass "esc / interrupt (post-esc state=$st)"

echo "=== cmd /compact accepted by peer ==="
# esc interrupts the turn but leaves the original prompt as a draft; C-u
# clears the input line so the peer returns to idle for the next test.
tmux -S "$SOCK" send-keys -t t:0.0 C-u
sleep 1
wait_state t:0.0 idle 30 || fail "not idle before /compact"
"$CLAUDE_DM" cmd t:0.0 "/compact"
wait_state t:0.0 idle 180 || fail "/compact did not leave peer idle within 180s"
pass "cmd /compact"

# The `answer` verb is NOT covered automatically because triggering a
# permission modal depends on the peer's settings (defaultMode, allowed-tools)
# and Claude Code's auto-approval heuristics for simple commands. In an
# environment where the peer has `defaultMode: bypassPermissions` in user
# settings (common for dev machines), no modal ever appears regardless of
# --permission-mode default on the CLI.
#
# Manual probe for the answer verb — run on a peer in default-permission mode:
#   claude-dm send t:0.0 "Use the Bash tool to run: curl https://example.com"
#   # peer should reach state=modal subtype=permission
#   claude-dm status t:0.0
#   claude-dm answer t:0.0 1   # pick "Yes"
#   # peer should return to idle with the command executed

echo
echo "e2e OK"
