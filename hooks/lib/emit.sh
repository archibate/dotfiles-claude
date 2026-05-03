#!/usr/bin/bash
# Shared helpers for emitting hook decision JSON.
#
# Usage: source this file from a hook, then call one of the helpers.
#
#   emit_post_tool_context "message"
#     Injects additionalContext into Claude's context on PostToolUse.
#
#   emit_pre_tool_deny "reason"
#     Denies the tool call on PreToolUse with the given reason shown to Claude.
#
#   emit_pre_tool_warn "hint"
#     Allows the tool call on PreToolUse but injects additionalContext, so Claude
#     gets a non-blocking advisory before the tool runs (useful for soft signals
#     where a hard-deny would be too noisy).

emit_post_tool_context() {
    jq -n --arg ctx "$1" '{
      hookSpecificOutput: {
        hookEventName: "PostToolUse",
        additionalContext: $ctx
      }
    }'
}

emit_pre_tool_deny() {
    jq -n --arg reason "$1" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $reason
      }
    }'
}

# emit_pre_tool_deny_bypassable <marker> <reason> — append the standard
# "how to bypass" footer to <reason> and emit the deny. Centralizes the
# boilerplate so wording stays consistent across hooks. The footer is worded
# to disambiguate "command" as the literal Bash tool command string (which
# the bypass scanner reads), not the script file the command happens to run.
emit_pre_tool_deny_bypassable() {
    local marker="$1" reason="$2"
    emit_pre_tool_deny "${reason}
If legitimate or false-positive, append \`# ${marker}\` to the Bash command."
}

# emit_pre_tool_warn "hint" — non-blocking advisory. It injects `hint` into
# Claude's context without setting permissionDecision, so normal permission
# handling still applies.
emit_pre_tool_warn() {
    jq -n --arg ctx "$1" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        additionalContext: $ctx
      }
    }'
}
