#!/usr/bin/env bash
set -euo pipefail

REPO="git@github.com:archibate/dotfiles-claude.git"
TARGET="$HOME/.claude"

if [ -d "$TARGET/.git" ]; then
    git -C "$TARGET" pull --ff-only
elif [ -d "$TARGET" ]; then
    git -C "$TARGET" init
    git -C "$TARGET" remote add origin "$REPO" 2>/dev/null ||
        git -C "$TARGET" remote set-url origin "$REPO"
    git -C "$TARGET" fetch origin
    git -C "$TARGET" checkout -f -B main origin/main
else
    git clone "$REPO" "$TARGET"
fi

echo "Shell integration (add to your rc file):"
echo "  bash/zsh: source ~/.claude/integration.sh"
echo "  fish:     source ~/.claude/integration.fish"
