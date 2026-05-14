#!/usr/bin/env bash

export CLAUDE_CONFIG_DIR=~/.claude-mocking-nest
mkdir -p $CLAUDE_CONFIG_DIR
cd ${TMPDIR-/tmp}
CLAUDE_AGENT_SDK_DISABLE_BUILTIN_AGENTS=1 CLAUDE_CODE_EXTRA_BODY='{"temperature":0}' CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 ENABLE_CLAUDEAI_MCP_SERVERS=false CLAUDE_CODE_DISABLE_CLAUDE_MDS=1 CLAUDE_CODE_DISABLE_POLICY_SKILLS=1 AUDIT_BACKEND=none CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT=1 claude --model haiku --effort low --thinking disabled --exclude-dynamic-system-prompt-sections --tools '' --agent assistant --system-prompt '' --permission-mode dontAsk --agents '{"assistant": {"description": "A helpful assistant", "prompt": "You are a helpful assistant."}}' "$@"
