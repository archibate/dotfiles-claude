#!/usr/bin/bash
# PreToolUse hook: when Claude is about to Write/Edit/MultiEdit a file under
# any `.claude/` directory (user-global ~/.claude/... or project-local
# <repo>/.claude/...), nudge it to consult the `claude-code-guide` subagent
# for current official docs BEFORE committing to a change. Fires at most once
# per session_id to avoid re-prompting on iterative edits.
#
# Why: settings.json, hooks, agents, skills, and slash-command schemas evolve
# quickly. Claude's training data lags the live docs, so editing a Claude
# config from prior knowledge often produces stale or invalid configurations.
# The claude-code-guide subagent fetches current Anthropic docs on demand.
set -euo pipefail

source "$(dirname "$0")/lib/emit.sh"
source "$(dirname "$0")/lib/read_input.sh"

read_file_path

# Match a `.claude/` directory segment anywhere in the path. A leading-segment
# `.claudeignore` or `foo.claude/bar` does not match because the `.claude`
# component must be bracketed by `/` on both sides (or be the leading segment
# in a relative path).
case "$file_path" in
    */.claude/*|.claude/*) ;;
    *) exit 0 ;;
esac

SID=$(jq -r '.session_id // "unknown"' <<< "$input")
CACHE_DIR=/tmp/claude-hint-agent-claude-code-guide
CACHE="$CACHE_DIR/$SID"
mkdir -p "$CACHE_DIR"
[ -f "$CACHE" ] && exit 0
touch "$CACHE"

emit_pre_tool_warn 'About to edit a Claude config file under `.claude/` (settings.json, hook, agent, skill, slash-command, plugin, etc.). Before committing to a change, spawn the `claude-code-guide` subagent via the Agent tool to fetch the current official Claude Code / Agent SDK / API docs for whatever schema or feature you are touching — formats and field names may have shifted since training. Skip only if the edit is a pure rename, typo fix, or value tweak that does not depend on schema.'
