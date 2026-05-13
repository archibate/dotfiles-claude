#!/usr/bin/env bash
set -euo pipefail

payload=$(mktemp)
trap 'rm -f "$payload"' EXIT
jq '.' > "$payload"

file_path=$(jq -r '.tool_input.file_path // .tool_response.filePath // empty' "$payload")
if [[ -z "$file_path" || ! -f "$file_path" ]]; then
    exit 0
fi

case "$file_path" in
    *.c|*.cc|*.cpp|*.cxx|*.h|*.hh|*.hpp|*.hxx)
        ;;
    *)
        exit 0
        ;;
esac

find_upward_file() {
    local start_dir=$1
    local name=$2
    local dir=$start_dir

    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/$name" ]]; then
            printf '%s\n' "$dir/$name"
            return 0
        fi
        dir=$(dirname "$dir")
    done

    return 1
}

find_upward_dir_containing() {
    local start_dir=$1
    local name=$2
    local dir=$start_dir

    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/$name" ]]; then
            printf '%s\n' "$dir"
            return 0
        fi
        dir=$(dirname "$dir")
    done

    return 1
}

file_dir=$(dirname "$file_path")
default_clang_format="$HOME/.claude/formatters/cpp/.clang-format"
default_clang_tidy="$HOME/.claude/formatters/cpp/.clang-tidy"
clang_format_config=$(find_upward_file "$file_dir" .clang-format || true)
clang_tidy_config=$(find_upward_file "$file_dir" .clang-tidy || true)
compile_commands_dir=$(find_upward_dir_containing "$file_dir" compile_commands.json || true)
messages=()

if ! command -v clang-format >/dev/null 2>&1; then
    messages+=("clang-format not found; C++ formatting did not run for $file_path")
elif [[ -n "$clang_format_config" ]]; then
    clang-format -i --style="file:$clang_format_config" "$file_path"
elif [[ -f "$default_clang_format" ]]; then
    clang-format -i --style="file:$default_clang_format" "$file_path"
else
    messages+=("No .clang-format found; C++ formatting did not run for $file_path")
fi

if ! command -v clang-tidy >/dev/null 2>&1; then
    messages+=("clang-tidy not found; C++ tidy did not run for $file_path")
elif [[ -n "$clang_tidy_config" ]]; then
    if [[ -n "$compile_commands_dir" ]]; then
        clang-tidy --quiet -p "$compile_commands_dir" "$file_path"
    else
        clang-tidy --quiet "$file_path" -- -std=c++17
    fi
elif [[ -f "$default_clang_tidy" ]]; then
    if [[ -n "$compile_commands_dir" ]]; then
        clang-tidy --quiet --config-file="$default_clang_tidy" -p "$compile_commands_dir" "$file_path"
    else
        clang-tidy --quiet --config-file="$default_clang_tidy" "$file_path" -- -std=c++17
    fi
else
    messages+=("No .clang-tidy found; C++ tidy did not run for $file_path")
fi

if (( ${#messages[@]} > 0 )); then
    printf '%s\n' "${messages[@]}" | jq -Rs '{hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:.}}'
fi
