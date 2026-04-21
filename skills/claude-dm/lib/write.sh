# shellcheck shell=bash
# Write verbs. All writes go through safe_to_dm unless --force is passed.

# Send prose. Single-line uses send-keys -l; multi-line uses bracketed paste so
# embedded newlines insert into the buffer rather than submit.
dm_send() {
  local target="$1" msg="$2" force="${3:-}"
  if [[ "$force" != "--force" ]]; then
    safe_to_dm "$target" || die "peer $target not in a safe state (use --force to override)"
  fi
  if [[ "$msg" == *$'\n'* ]]; then
    printf '%s' "$msg" | tm load-buffer -
    tm paste-buffer -t "$target" -p
  else
    tm send-keys -t "$target" -l -- "$msg"
  fi
  tm send-keys -t "$target" Enter
  audit send "$target: $msg"
}

# Slash-command tiers. Red commands are irreversible for the peer and require --confirm.
cmd_tier() {
  case "$1" in
    /clear|/exit|/resume|/reset) printf 'red\n'  ;;
    /compact|/loop|/schedule)    printf 'yellow\n' ;;
    *)                           printf 'green\n'  ;;
  esac
}

# Send a slash command. --confirm unlocks red tier; --force skips safety gate.
dm_cmd() {
  local target="$1" cmd="$2"; shift 2
  [[ "$cmd" == /* ]] || die "not a slash command: $cmd"

  local force=0 confirm=0
  for a in "$@"; do
    case "$a" in
      --force)   force=1 ;;
      --confirm) confirm=1 ;;
      *) die "unknown flag: $a" ;;
    esac
  done

  local tier; tier=$(cmd_tier "${cmd%% *}")
  if [[ "$tier" == "red" && "$confirm" -eq 0 ]]; then
    die "refusing red-tier command $cmd without --confirm"
  fi

  if [[ "$force" -eq 0 ]]; then
    safe_to_dm "$target" || die "peer $target not in a safe state (use --force)"
  fi

  tm send-keys -t "$target" -l -- "$cmd"
  tm send-keys -t "$target" Enter
  audit cmd "$target: $cmd (tier=$tier)"
}

# Emergency interrupt. Sends Escape: cancels peer's in-flight turn, dismisses
# modals, clears autocomplete. Refuses on drafting (would wipe human's draft).
dm_esc() {
  local target="$1" force="${2:-}"
  local state; state=$(peer_state "$target")
  if [[ "$state" == "drafting" && "$force" != "--force" ]]; then
    die "peer $target is drafting; --force to esc anyway (will clear human's draft)"
  fi
  tm send-keys -t "$target" Escape
  audit esc "$target (state=$state)"
}

# Answer a modal (permission or AskUserQuestion) with a single keystroke.
# Typical values: 1, 2, 3 (numbered shortcut); some modals also accept y/n/a.
dm_answer() {
  local target="$1" key="$2" force="${3:-}"
  [[ -n "$key" ]] || die "answer key required (e.g. 1, 2, 3)"
  if [[ "$force" != "--force" ]]; then
    local state; state=$(peer_state "$target")
    [[ "$state" == "modal" ]] || die "peer $target not in modal (state=$state); --force to override"
  fi
  tm send-keys -t "$target" -l -- "$key"
  audit answer "$target: $key"
}

dm_ask() {
  local target="$1" msg="$2" timeout="${3:-120}"
  local tag tr start_lines=0 waited=0
  tag="DONE-$(date +%s%N)"

  # Fresh sessions have no transcript yet; start_lines stays 0 until send creates it.
  if tr=$(target_transcript "$target" 2>/dev/null); then
    start_lines=$(wc -l <"$tr")
  fi

  dm_send "$target" "$msg

Please end your reply with the sentinel: $tag"

  while (( waited < timeout )); do
    if tr=$(target_transcript "$target" 2>/dev/null); then
      local assistant_text
      assistant_text=$(tail -n +"$((start_lines + 1))" "$tr" \
        | jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text')
      if grep -qF "$tag" <<<"$assistant_text"; then
        sed "/$tag/Q" <<<"$assistant_text"
        return 0
      fi
    fi
    sleep 2
    waited=$((waited + 2))
  done
  die "timeout waiting for reply sentinel $tag on $target"
}
