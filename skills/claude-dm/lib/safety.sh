# shellcheck shell=bash
# Peer state classification. Pane-visible state drives the top-level state;
# transcript is consulted as an authority check and for modal subtype.

# Returns one of: idle | busy | drafting | modal | other (on stdout).
peer_state() {
  local target="$1"
  local title; title=$(target_title "$target")
  case "$title" in
    '✳'*) ;;
    *)    printf 'busy\n'; return 0 ;;
  esac

  local body
  body=$(tm capture-pane -p -J -t "$target" 2>/dev/null) || { printf 'other\n'; return 0; }
  body=$(tail -n 15 <<<"$body")
  # Claude Code pads the input line with NBSP (U+00A0); normalize to ASCII space.
  body=$(sed $'s/\xc2\xa0/ /g' <<<"$body")

  grep -qP '^─{10,}$' <<<"$body" || { printf 'other\n'; return 0; }
  grep -qP '^❯ '      <<<"$body" || { printf 'other\n'; return 0; }

  local box draft menu_lines
  box=$(awk '/^─{10,}$/ { if (inside) exit; inside=1; next } inside { print }' <<<"$body")
  draft=$(tr -d '❯ \t\n' <<<"$box")
  if [[ -z "$draft" ]]; then
    printf 'idle\n'; return 0
  fi

  # Non-empty box: a menu (2+ numbered options) indicates a modal; otherwise a draft.
  menu_lines=$(grep -cE '^[[:space:]❯]*[0-9]+[.)]' <<<"$box" || true)
  if (( menu_lines >= 2 )); then
    printf 'modal\n'
  else
    printf 'drafting\n'
  fi
}

# When state is `modal`, return its subtype by looking at the peer's most recent
# unmatched tool_use in the transcript: permission | question | other.
modal_subtype() {
  local target="$1" tr name
  tr=$(target_transcript "$target") || { printf 'other\n'; return 0; }
  name=$(tac "$tr" \
    | jq -rc 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use") | .name' \
    | head -n 1)
  case "$name" in
    AskUserQuestion)              printf 'question\n'   ;;
    Bash|Edit|Write|NotebookEdit) printf 'permission\n' ;;
    '')                           printf 'other\n'      ;;
    *)                            printf 'permission\n' ;;
  esac
}

# Transcript sanity check: reject only if the most recent assistant turn has a
# non-terminal stop_reason (e.g. tool_use pending result). Pane state is the
# authoritative liveness signal; this catches the narrow mid-tool case where
# the UI might briefly show idle while the transcript says a tool is in flight.
# User-only tails (fresh / interrupted sessions) and no-transcript cases pass.
check_transcript_end_turn() {
  local tr
  tr=$(target_transcript "$1") || return 0
  local last_type last_stop
  read -r last_type last_stop < <(tac "$tr" \
    | jq -rc 'select(.type=="assistant" or .type=="user") | "\(.type) \(.message.stop_reason // "")"' \
    | head -n 1) || true
  if [[ "$last_type" == "assistant" && "$last_stop" != "end_turn" && -n "$last_stop" ]]; then
    printf 'last assistant turn stop=%s\n' "$last_stop"
    return 1
  fi
  return 0
}

# True iff state is idle AND transcript confirms end_turn. Prints reason on stderr.
safe_to_dm() {
  local target="$1" state reason
  state=$(peer_state "$target")
  if [[ "$state" != "idle" ]]; then
    printf 'state=%s\n' "$state" >&2; return 1
  fi
  reason=$(check_transcript_end_turn "$target") || { printf 'transcript %s\n' "$reason" >&2; return 1; }
}
