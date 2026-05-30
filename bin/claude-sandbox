#!/usr/bin/env bash

claude --thinking-display summarized --allow-dangerously-skip-permissions --exclude-dynamic-system-prompt-sections --permission-mode acceptEdits --settings '{"sandbox": {"enabled": true, "autoAllowBashIfSandboxed": true, "filesystem": {"allowWrite": [".", "/tmp"]}}' "$@"
