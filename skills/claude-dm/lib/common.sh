# shellcheck shell=bash
# Shared helpers. Sourced by the dispatcher and all other lib files.

: "${CLAUDE_DM_SOCKET:=/tmp/tmux-$(id -u)/default}"
: "${CLAUDE_DM_LOG:=$HOME/.claude/claude-dm.log}"
: "${CLAUDE_SESSIONS_DIR:=$HOME/.claude/sessions}"
: "${CLAUDE_PROJECTS_DIR:=$HOME/.claude/projects}"

SOCKET="$CLAUDE_DM_SOCKET"

tm() { tmux -S "$SOCKET" "$@"; }

die() { printf 'claude-dm: %s\n' "$*" >&2; exit 1; }
warn() { printf 'claude-dm: %s\n' "$*" >&2; }

audit() {
  printf '%s\t%s\t%s\n' "$(date -Iseconds)" "$1" "$2" >> "$CLAUDE_DM_LOG"
}

# pane_pid -> claude pid. When tmux launches a shell, pane_pid is the shell
# and claude is its child. When tmux launches claude directly (e.g. `new-session
# '... claude'`), pane_pid itself is claude.
pane_to_claude_pid() {
  local pid="$1" comm
  comm=$(ps -o comm= -p "$pid" 2>/dev/null | tr -d ' ')
  if [[ "$comm" == "claude" ]]; then
    printf '%s\n' "$pid"
    return 0
  fi
  pgrep -P "$pid" -x claude 2>/dev/null | head -n 1
}

# target -> pane_pid (shell leader, not the claude process itself)
target_pane_pid() {
  tm display-message -p -t "$1" '#{pane_pid}' 2>/dev/null
}

# target -> claude pid (the process whose sessionId we care about)
target_pid() {
  local pp cp
  pp=$(target_pane_pid "$1") || return 1
  [[ -n "$pp" ]] || return 1
  cp=$(pane_to_claude_pid "$pp")
  [[ -n "$cp" ]] || return 1
  printf '%s\n' "$cp"
}

# target -> current pane_title
target_title() {
  tm display-message -p -t "$1" '#{pane_title}' 2>/dev/null
}

# target -> pane_current_command
target_cmd() {
  tm display-message -p -t "$1" '#{pane_current_command}' 2>/dev/null
}

# pid -> sessionId (via ~/.claude/sessions/<pid>.json)
pid_to_sid() {
  local pid="$1" f="$CLAUDE_SESSIONS_DIR/$1.json"
  [[ -f "$f" ]] || return 1
  jq -r '.sessionId // empty' "$f"
}

# sessionId -> transcript jsonl path (first match)
sid_to_transcript() {
  local sid="$1"
  local match
  match=$(find "$CLAUDE_PROJECTS_DIR" -maxdepth 2 -name "$sid.jsonl" -print -quit 2>/dev/null)
  [[ -n "$match" ]] || return 1
  printf '%s\n' "$match"
}

# target -> transcript path
target_transcript() {
  local pid sid
  pid=$(target_pid "$1") || return 1
  [[ -n "$pid" ]] || return 1
  sid=$(pid_to_sid "$pid") || return 1
  sid_to_transcript "$sid"
}

# Resolve the current pane to a session:window.pane addr on its tmux socket.
# Honours the actual socket from $TMUX (not CLAUDE_DM_SOCKET) since "self" must
# target the real running pane. Mutates SOCKET so subsequent tm() calls follow.
# Prints addr; returns nonzero with a warning if not running inside tmux.
self_target() {
  [[ -n "${TMUX:-}" ]]      || { warn "not running inside tmux"; return 1; }
  [[ -n "${TMUX_PANE:-}" ]] || { warn "TMUX_PANE not set"; return 1; }
  SOCKET="${TMUX%%,*}"
  tmux -S "$SOCKET" display-message -p -t "$TMUX_PANE" \
    '#{session_name}:#{window_index}.#{pane_index}' 2>/dev/null
}

# Walk PPID chain to find this session's claude pid.
self_claude_pid() {
  local pid="$PPID" comm
  while [[ -n "$pid" && "$pid" -gt 1 ]]; do
    comm=$(ps -o comm= -p "$pid" 2>/dev/null | tr -d ' ')
    [[ "$comm" == "claude" ]] && { printf '%s\n' "$pid"; return 0; }
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
  done
  return 1
}

# Stderr hint when self can't appear in the roster: (a) not in tmux (only
# fires if $CLAUDECODE is set — silent for non-Claude callers), or (b) tmux
# socket differs from $CLAUDE_DM_SOCKET. Stdout untouched.
warn_self_unlisted() {
  if [[ -z "${TMUX:-}" ]]; then
    [[ -n "${CLAUDECODE:-}" ]] || return 0
    local cpid sid
    cpid=$(self_claude_pid || true)
    sid=$(pid_to_sid "${cpid:-0}" 2>/dev/null || true)
    warn "self not listed: not in tmux (pid=${cpid:-?} sid=${sid:-?}). Ask user to re-spawn yourself inside tmux to be addressable."
    return 0
  fi
  local self_sock="${TMUX%%,*}" addr
  [[ "$self_sock" == "$SOCKET" ]] && return 0
  addr=$(tmux -S "$self_sock" display-message -p -t "${TMUX_PANE:-}" \
    '#{session_name}:#{window_index}.#{pane_index}' 2>/dev/null || true)
  warn "self not listed: on socket $self_sock (as ${addr:-?}), listing $SOCKET. Try CLAUDE_DM_SOCKET=$self_sock."
}
