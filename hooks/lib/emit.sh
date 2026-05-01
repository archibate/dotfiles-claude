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

# emit_pre_tool_warn "hint" — non-blocking advisory: lets the tool call proceed
# (permissionDecision: allow) while injecting `hint` into Claude's context so
# it can react if the call fails downstream. Use when the hook has useful but
# not authoritative information about an impending tool call.
emit_pre_tool_warn() {
    jq -n --arg ctx "$1" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "allow",
        additionalContext: $ctx
      }
    }'
}
