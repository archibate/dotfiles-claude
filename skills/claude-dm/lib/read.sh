# shellcheck shell=bash
# Read-only verbs: roster, peek, tail.

# Format an elapsed-seconds count into a compact "17s" / "8m" / "1h21m" /
# "3d20h" string. Empty input yields "-" (peer has no resolved transcript).
fmt_elapsed() {
  local s="$1"
  [[ -z "$s" || "$s" == "-" ]] && { printf '-'; return; }
  if   (( s < 60    )); then printf '%ds' "$s"
  elif (( s < 3600  )); then printf '%dm' "$((s/60))"
  elif (( s < 86400 )); then printf '%dh%dm' "$((s/3600))" "$(((s%3600)/60))"
  else                       printf '%dd%dh' "$((s/86400))" "$(((s%86400)/3600))"
  fi
}

# Emit TSV: addr, pid, state(idle|busy), last_activity, sessionId, title
# LAST column shows seconds since the transcript JSONL was last written
# (assistant output, tool result, or user prompt — anything appended).
# Self-row gets a trailing '*' on ADDR (display-only marker; strip before
# passing to other verbs). Self is detected only when $CLAUDE_DM_SOCKET
# matches the socket from $TMUX; cross-socket runs show no marker.
dm_roster() {
  local self_addr=""
  if [[ -n "${TMUX:-}" && -n "${TMUX_PANE:-}" && "${TMUX%%,*}" == "$SOCKET" ]]; then
    self_addr=$(tm display-message -p -t "$TMUX_PANE" \
      '#{session_name}:#{window_index}.#{pane_index}' 2>/dev/null || true)
  fi

  local now; now=$(date +%s)

  # No pre-filter on pane_current_command: when execve received the resolved
  # version path (basename "2.1.X") rather than the "claude" symlink, comm and
  # therefore #{pane_current_command} hold the version string, not "claude".
  # pane_to_claude_pid is the authoritative gate.
  tm list-panes -a \
      -F '#{pane_pid}	#{session_name}:#{window_index}.#{pane_index}	#{pane_title}' \
    | while IFS=$'\t' read -r pane_pid addr title; do
        local state cpid sid marker="" tr mtime last
        cpid=$(pane_to_claude_pid "$pane_pid") || continue
        case "$title" in
          '✳'*) state='idle'  ;;
          *)    state='busy'  ;;
        esac
        sid=$(pid_to_sid "$cpid" || true)
        last="-"
        if [[ -n "$sid" ]]; then
          tr=$(sid_to_transcript "$sid" 2>/dev/null || true)
          if [[ -n "$tr" ]]; then
            mtime=$(stat -c '%Y' "$tr" 2>/dev/null || true)
            [[ -n "$mtime" ]] && last=$(fmt_elapsed "$(( now - mtime ))")
          fi
        fi
        [[ -n "$self_addr" && "$addr" == "$self_addr" ]] && marker="*"
        printf '%s%s\t%s\t%s\t%s\t%s\t%s\n' "$addr" "$marker" "$cpid" "$state" "$last" "$sid" "$title"
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

# Block until peer reaches a terminal state, then emit a sentinel line
# followed by a `hint:` line that tells the orchestrator agent to re-arm.
# DONE  — peer satisfies the same gate as safe_to_dm: pane title is ✳
#         AND the transcript's last assistant turn is end_turn (no pending
#         tool_use). Title-idle alone is not enough — UI can briefly show ✳
#         while a tool result is still in flight.
# MODAL — peer is waiting on a permission / question modal (needs intervention)
# Polls peer_state every interval_s (default 30). If timeout_s > 0, gives up
# after that many seconds with stderr message and exit 1. If debounce_s > 0,
# the DONE gate must remain satisfied for that many consecutive seconds before
# firing — useful when the peer chains short tool-result turns and could
# transiently appear DONE between them. Effective resolution is one poll
# interval; debounce_s < interval_s collapses to "fire on the second
# consecutive idle poll". Re-checks target_pid each iteration so a vanished
# pane breaks the loop instead of looping forever (peer_state falls through
# to 'busy' when target_title returns empty).
dm_wait() {
  local target="$1" interval="${2:-30}" timeout="${3:-0}" debounce="${4:-0}"
  target_pid "$target" >/dev/null 2>&1 || die "no such pane: $target"

  local elapsed=0 state nap idle_since=-1
  while true; do
    target_pid "$target" >/dev/null 2>&1 || { warn "pane gone: $target"; return 1; }
    state=$(peer_state "$target")
    case "$state" in
      idle)
        # Pane title can read ✳ briefly while the transcript still has a
        # non-end_turn assistant turn (tool result pending). Match safe_to_dm:
        # require both signals before declaring DONE; otherwise keep polling.
        if check_transcript_end_turn "$target" >/dev/null; then
          if (( debounce <= 0 )); then
            printf 'DONE\n'
            printf 'hint: peer reached idle. After dispatching the next action, re-arm with: claude-dm wait %s\n' "$target"
            return 0
          fi
          if (( idle_since < 0 )); then
            idle_since=$elapsed
          elif (( elapsed - idle_since >= debounce )); then
            printf 'DONE\n'
            printf 'hint: peer held idle %ds. After dispatching the next action, re-arm with: claude-dm wait %s\n' "$debounce" "$target"
            return 0
          fi
        else
          idle_since=-1
        fi
        ;;
      modal)
        printf 'MODAL\n'
        printf 'hint: peer needs intervention. Inspect with `claude-dm status %s`; after resolving via `answer`/`esc`/`send`, re-arm with: claude-dm wait %s\n' "$target" "$target"
        return 0
        ;;
      *)
        idle_since=-1
        ;;
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
