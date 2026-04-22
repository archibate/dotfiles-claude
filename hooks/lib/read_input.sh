#!/usr/bin/bash
# Shared stdin-parsing helpers for PreToolUse / PostToolUse hooks.
#
# Each helper reads the hook JSON payload from stdin, extracts a common field,
# and exits 0 (allowing the tool call) if that field is empty — so hooks can
# start with a one-line prologue instead of open-coding the jq dance.
#
#   read_bash_command  — Bash tool hooks: sets $input + $command
#   read_file_path     — Edit/Write/Read hooks: sets $input + $file_path

read_bash_command() {
    input=$(cat)
    command=$(jq -r '.tool_input.command // ""' <<< "$input")
    [ -n "$command" ] || exit 0
}

# read_file_path — for hooks reacting to Edit/Write/Read events.
# Sets $input and $file_path; exits 0 if neither .tool_input.file_path
# nor the legacy .tool_input.file is set.
read_file_path() {
    input=$(cat)
    file_path=$(jq -r '.tool_input.file_path // .tool_input.file // ""' <<< "$input")
    [ -n "$file_path" ] || exit 0
}
