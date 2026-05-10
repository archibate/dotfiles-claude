# shellcheck shell=bash
# Read-only verbs: roster, peek, tail.

# Emit TSV: addr, pid, state(idle|busy), sessionId, title
# Self-row gets a trailing '*' on ADDR (display-only marker; strip before
# passing to other verbs). Self is detected only when $CLAUDE_DM_SOCKET
# matches the socket from $TMUX; cross-socket runs show no marker.
dm_roster() {
  local self_addr=""
  if [[ -n "${TMUX:-}" && -n "${TMUX_PANE:-}" && "${TMUX%%,*}" == "$SOCKET" ]]; then
    self_addr=$(tm display-message -p -t "$TMUX_PANE" \
      '#{session_name}:#{window_index}.#{pane_index}' 2>/dev/null || true)
  fi

  tm list-panes -a \
      -F '#{pane_pid}	#{session_name}:#{window_index}.#{pane_index}	#{pane_current_command}	#{pane_title}' \
    | awk -F'\t' '$3=="claude"' \
    | while IFS=$'\t' read -r pane_pid addr _cmd title; do
        local state cpid sid marker=""
        case "$title" in
          '✳'*) state='idle'  ;;
          *)    state='busy'  ;;
        esac
        cpid=$(pane_to_claude_pid "$pane_pid")
        [[ -n "$cpid" ]] || continue
        sid=$(pid_to_sid "$cpid" || true)
        [[ -n "$self_addr" && "$addr" == "$self_addr" ]] && marker="*"
        printf '%s%s\t%s\t%s\t%s\t%s\n' "$addr" "$marker" "$cpid" "$state" "$sid" "$title"
      done
}

dm_peek() {
  local target="$1" n="${2:-30}"
  local tr
  tr=$(target_transcript "$target") || die "no transcript for $target"
  jq -r '
    select(.type=="assistant")
    | .message.content[]?
    | select(.type=="text")
    | .text
  ' "$tr" | tail -n "$n"
}

dm_tail() {
  local target="$1"
  local tr
  tr=$(target_transcript "$target") || die "no transcript for $target"
  tail -n 0 -F "$tr" | jq -rc --unbuffered '
    if .type=="assistant" then
      (.message.content[]? | select(.type=="text") | "A> " + .text),
      (.message.content[]? | select(.type=="tool_use") | "A> [tool] " + .name + " " + (.input|tostring|.[0:200]))
    elif .type=="user" then
      if (.message.content|type)=="string" then "U> " + .message.content
      else (.message.content[]? | select(.type=="text") | "U> " + .text)
      end
    else empty
    end
  '
}

# Block until peer reaches a terminal state, then emit one sentinel line.
# DONE  — peer satisfies the same gate as safe_to_dm: pane title is ✳
#         AND the transcript's last assistant turn is end_turn (no pending
#         tool_use). Title-idle alone is not enough — UI can briefly show ✳
#         while a tool result is still in flight.
# MODAL — peer is waiting on a permission / question modal (needs intervention)
# Polls peer_state every interval_s (default 30). If timeout_s > 0, gives up
# after that many seconds with stderr message and exit 1. Re-checks target_pid
# each iteration so a vanished pane breaks the loop instead of looping forever
# (peer_state falls through to 'busy' when target_title returns empty).
dm_wait() {
  local target="$1" interval="${2:-30}" timeout="${3:-0}"
  target_pid "$target" >/dev/null 2>&1 || die "no such pane: $target"

  local elapsed=0 state nap
  while true; do
    target_pid "$target" >/dev/null 2>&1 || { warn "pane gone: $target"; return 1; }
    state=$(peer_state "$target")
    case "$state" in
      idle)
        # Pane title can read ✳ briefly while the transcript still has a
        # non-end_turn assistant turn (tool result pending). Match safe_to_dm:
        # require both signals before declaring DONE; otherwise keep polling.
        if check_transcript_end_turn "$target" >/dev/null; then
          printf 'DONE\n'; return 0
        fi
        ;;
      modal) printf 'MODAL\n'; return 0 ;;
    esac
    if (( timeout > 0 && elapsed >= timeout )); then
      warn "timeout after ${timeout}s (state=$state)"
      return 1
    fi
    # Cap sleep to remaining budget so timeout fires within timeout_s even
    # when caller passed interval > remaining.
    if (( timeout > 0 && interval > timeout - elapsed )); then
      nap=$(( timeout - elapsed ))
    else
      nap=$interval
    fi
    sleep "$nap"
    elapsed=$(( elapsed + nap ))
  done
}
