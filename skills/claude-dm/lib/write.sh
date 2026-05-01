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
    # Claude Code needs a moment to finish consuming the bracketed-paste
    # sequence before Enter; without the gap, Enter lands mid-paste and is
    # treated as a newline in the buffer instead of submit.
    sleep 0.2
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

# Self-trigger an allowlisted user-only slash command on the current pane.
# Forks a background daemon that waits for the agent's current turn to end,
# then injects the slash command followed by a wake-up notification at
# peer-idle (see the daemon block below for why deferring is required).
# Allowlist: /compact, /context, /rename. Other commands either destroy the
# session (/clear, /exit), or are already callable via the Skill tool (/loop,
# /schedule, custom skills). Refuses if the input box already has a draft or
# modal, or if the box state is unparseable.
dm_self() {
  local cmd="$1"
  [[ "$cmd" == /* ]] || die "not a slash command: $cmd"
  local base="${cmd%% *}"
  case "$base" in
    /compact|/context|/rename) ;;
    *) die "self-DM allowlist is /compact, /context, /rename (got: $cmd)" ;;
  esac

  local target; target=$(self_target) || die "self_target failed (must run inside a tmux pane)"
  [[ -n "$target" ]] || die "could not resolve current tmux pane"

  local box; box=$(peer_box_state "$target")
  case "$box" in
    empty)    ;;
    drafting) die "input box has unsubmitted text on $target; refusing to clobber draft" ;;
    modal)    die "modal active in input box on $target; refusing to inject" ;;
    unknown)  die "could not parse input box on $target; refusing self-DM" ;;
  esac

  # Background daemon: wait for the agent's current turn to end, then inject
  # the slash command followed by a wake-up notification. Both keystrokes go
  # in at peer-idle so /context runs cleanly and its output bundles into the
  # notification user message — the agent receives one real user turn that
  # contains the slash output AND the wake-up cue.
  #
  # Why background: the caller is the agent itself, mid-turn. send-keys at
  # this moment lands in a live input box and gets submitted prematurely
  # (slash output orphaned, notification arrives as an interrupt). Deferring
  # to peer-idle makes the sequence behave as if the user had typed it after
  # the turn ended.
  (
    # Wait for the agent's turn to fully end. Two idle signals, either suffices:
    #   (a) peer_state == idle (title shows ✳)
    #   (b) transcript file unmodified for ≥ QUIET_S seconds AND box empty
    # (b) is necessary because some sessions have stop-hook feedback loops that
    # keep the title busy for minutes — but the transcript stops growing once
    # the loop terminates. 0.5s polling × 1200 = 10 min cap.
    QUIET_S=3
    tr=$(target_transcript "$target" 2>/dev/null || true)
    polls=0
    fired=0
    while (( polls < 1200 )); do
      if [[ "$(peer_state "$target")" == "idle" ]]; then fired=1; break; fi
      if [[ -n "$tr" && -f "$tr" ]]; then
        mtime=$(stat -c %Y "$tr" 2>/dev/null || echo 0)
        now=$(date +%s)
        if (( now - mtime >= QUIET_S )) && [[ "$(peer_box_state "$target")" == "empty" ]]; then
          fired=1; break
        fi
      fi
      sleep 0.5
      polls=$((polls + 1))
    done
    if (( fired == 0 )); then
      audit self "$target: $cmd (timeout waiting for idle, daemon gave up)"
      exit 1
    fi
    # Re-check the box at idle; refuse if a draft or modal appeared while we
    # were waiting (would clobber the user's input).
    case "$(peer_box_state "$target")" in
      empty) ;;
      *) audit self "$target: $cmd (box not empty at idle, daemon gave up)"; exit 1 ;;
    esac
    tm send-keys -t "$target" -l -- "$cmd"
    tm send-keys -t "$target" Enter
    sleep 0.5
    tm send-keys -t "$target" -l -- "<notification>claude-dm self $cmd dispatched; output above</notification>"
    tm send-keys -t "$target" Enter
    audit self "$target: $cmd (fired at idle, polls=$polls)"
  ) &
  disown
  audit self "$target: $cmd (queued for post-turn wake-up)"
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
