#!/usr/bin/bash
# PreToolUse hook: when Claude is about to drive a Chrome/Chromium binary in
# headless mode by hand (`chromium --headless ...`), advertise the
# /agent-browser skill instead — it wraps Chrome/Chromium over CDP with
# snapshot/click/fill/screenshot verbs and a persistent daemon, so it replaces
# raw `--headless` flag-juggling and one-shot screenshot scripts.
#
# Fires at most once per session_id (re-arms after auto-compact, like the
# sibling hint-skill-* hooks). Non-blocking by design — emits additionalContext
# and lets the command run; a hard-deny would be too noisy for an advisory.
#
# Discriminator: the `--headless` flag carries the specificity, so binary
# matching is deliberately lenient — path prefixes (`/usr/bin/chromium`) and
# wrappers (`xvfb-run chromium --headless`, `timeout 30 chromium --headless`)
# all fire, which command-position-only anchoring would miss. The residual FP
# (a literal `chromium --headless` inside an echo/commit message) is harmless:
# a one-shot, non-blocking nudge.
set -euo pipefail

source "$(dirname "$0")/lib/emit.sh"
source "$(dirname "$0")/lib/session_lock.sh"
source "$(dirname "$0")/lib/read_input.sh"

read_bash_command

# Already using the skill's CLI — nothing to advertise.
case "$command" in *agent-browser*) exit 0 ;; esac

# Fire if either:
#   (a) an inherently-headless Chromium shell binary is invoked, or
#   (b) a Chrome/Chromium-family binary is invoked WITH the --headless flag.
# All three names below are the Chrome/Chromium headless-shell binary: the
# modern {chrome,chromium}-headless-shell and the legacy headless_shell (the
# [-_] also accepts the headless-shell spelling).
shell_re='\b(chromium-headless-shell|chrome-headless-shell|headless[-_]shell)\b'
chrome_re='\b(chromium(-browser)?|google-chrome(-stable)?|chrome)\b'
flag_re='--headless\b'

if grep -qP -- "$shell_re" <<< "$command"; then
    :
elif grep -qP -- "$chrome_re" <<< "$command" && grep -qP -- "$flag_re" <<< "$command"; then
    :
else
    exit 0
fi

SID=$(jq -r '.session_id // "unknown"' <<< "$input")

# Skip subagents — agent-* prefix on session_id. Short-lived subagents
# typically run a single browser command and don't have budget to load a skill.
case "$SID" in agent-*) exit 0 ;; esac

CACHE_DIR=/tmp/claude-${UID}-state/skill-hint-agent-browser
CACHE="$CACHE_DIR/$SID"
mkdir -p -m 700 "$CACHE_DIR"
reset_on_compact "$SID" "$CACHE_DIR" "$CACHE"
[ -f "$CACHE" ] && exit 0
touch "$CACHE"

emit_pre_tool_warn 'About to drive Chrome/Chromium headless by hand. Consider the /agent-browser skill — it wraps Chrome/Chromium over CDP with snapshot/click/fill/screenshot verbs and a persistent daemon, instead of raw `chromium --headless` flag-juggling. Load via Skill tool (skill='\''agent-browser'\''). Raw `chromium --headless` is fine for a one-off where the skill is unavailable. (One-shot hint — will not fire again this session.)'
