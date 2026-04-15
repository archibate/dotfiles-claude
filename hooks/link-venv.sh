#!/usr/bin/bash
# SessionStart hook: symlink .venv in all git worktrees to the main project's .venv
# so that `uv run` in any worktree finds already-installed packages.
set -euo pipefail

# Consume stdin (required by hook protocol)
cat > /dev/null

ref_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
main_root=$(git -C "$ref_dir" worktree list 2>/dev/null | head -1 | awk '{print $1}') || true

[ -n "$main_root" ] || exit 0

main_venv="$main_root/.venv"
[ -d "$main_venv" ] || exit 0

git -C "$main_root" worktree list 2>/dev/null | tail -n +2 | awk '{print $1}' | while read -r wt; do
    wt_venv="$wt/.venv"
    if [ -L "$wt_venv" ] && [ "$(readlink "$wt_venv")" = "$main_venv" ]; then
        continue
    fi
    rm -rf "$wt_venv"
    ln -s "$main_venv" "$wt_venv"
done
