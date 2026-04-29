#!/usr/bin/bash
# PreToolUse hook: deny invoking the bundled /schedule skill.
# /schedule creates remote routines on Anthropic's claude.ai cloud (CCR).
# This host is a persistent server, so local scheduling via CronCreate is
# preferred (survives across sessions, runs locally, no cloud dependency).
#
# Bypass when remote schedule is genuinely needed: include the token
# `BYPASS_REMOTE_SCHEDULE` in the skill args (e.g. /schedule BYPASS_REMOTE_SCHEDULE ...).
set -euo pipefail

source "$(dirname "$0")/lib/emit.sh"

input=$(cat)
skill=$(jq -r '.tool_input.skill // ""' <<< "$input")
args=$(jq -r '.tool_input.args // ""' <<< "$input")
skill="${skill#/}"

if echo "$args" | grep -qF "BYPASS_REMOTE_SCHEDULE"; then
    exit 0
fi

if [[ "$skill" == "schedule" ]]; then
    emit_pre_tool_deny "/schedule is disabled on this host. It schedules REMOTE routines on Anthropic's cloud (CCR), but this is a persistent server — use the harness-native CronCreate tool instead. CronCreate runs prompts/skills on a local cron schedule, persists across sessions, and uses local files/env. Companion tools: CronList, CronDelete. If you legitimately need a remote routine for this task, bypass by including the token \`BYPASS_REMOTE_SCHEDULE\` in the skill args."
fi

exit 0
