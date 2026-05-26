#!/usr/bin/env bash
set -euo pipefail

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    exit 0
fi

if ! command -v clang-tidy >/dev/null 2>&1; then
    exit 0
fi

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

if [[ ! -f .clang-tidy ]]; then
    exit 0
fi

compile_commands_dir=""
while IFS= read -r compile_commands_path; do
    compile_commands_dir=$(dirname "$compile_commands_path")
    break
done < <(fd -HI "compile_commands.json" "$repo_root")

files=()
while IFS= read -r file; do
    case "$file" in
        *.c|*.cc|*.cpp|*.cxx|*.h|*.hh|*.hpp|*.hxx)
            files+=("$file")
            ;;
    esac
done < <(
    {
        git diff --name-only --diff-filter=ACMRT HEAD --
        git ls-files --others --exclude-standard
    } | sort -u
)

if (( ${#files[@]} == 0 )); then
    exit 0
fi

for file in "${files[@]}"; do
    if [[ ! -f "$file" ]]; then
        continue
    fi
    if [[ -n "$compile_commands_dir" ]]; then
        clang-tidy --quiet -p "$compile_commands_dir" "$file" || true
    else
        clang-tidy --quiet "$file" -- -std=c++17 || true
    fi
done
