#!/usr/bin/env bash
set -euo pipefail

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    exit 0
fi

repo_root=$(git rev-parse --show-toplevel)
source_file="$HOME/.claude/formatters/cpp/.clang-tidy"
target_file="$repo_root/.clang-tidy"

if [[ ! -f "$source_file" || -f "$target_file" ]]; then
    exit 0
fi

cp "$source_file" "$target_file"
printf '%s\n' "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"Copied default .clang-tidy to $target_file\"}}"
