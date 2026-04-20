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
