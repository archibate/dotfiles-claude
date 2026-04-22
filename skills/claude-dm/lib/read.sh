# shellcheck shell=bash
# Read-only verbs: roster, peek, tail.

# Emit TSV: addr, pid, state(idle|busy), sessionId, title
dm_roster() {
  tm list-panes -a \
      -F '#{pane_pid}	#{session_name}:#{window_index}.#{pane_index}	#{pane_current_command}	#{pane_title}' \
    | awk -F'\t' '$3=="claude"' \
    | while IFS=$'\t' read -r pane_pid addr _cmd title; do
        local state cpid sid
        case "$title" in
          '✳'*) state='idle'  ;;
          *)    state='busy'  ;;
        esac
        cpid=$(pane_to_claude_pid "$pane_pid")
        [[ -n "$cpid" ]] || continue
        sid=$(pid_to_sid "$cpid" || true)
        printf '%s\t%s\t%s\t%s\t%s\n' "$addr" "$cpid" "$state" "$sid" "$title"
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
