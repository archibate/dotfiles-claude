#!/usr/bin/bash
# PostToolUse hook: display images in Kitty terminal after Read tool on image files
set -euo pipefail

# Resolve repo root relative to this hook script (hooks/ and skills/ share
# same parent). Using `cd && pwd -P` instead of `readlink -f` because BSD
# readlink (macOS) doesn't accept -f.
repo_root=$(cd "$(dirname "$0")/.." && pwd -P)
show_image_script="$repo_root/skills/show-image/scripts/show_image.py"

source "$(dirname "$0")/lib/read_input.sh"

read_file_path

ext=$(echo "$file_path" | sed 's/.*\.//' | tr '[:upper:]' '[:lower:]')

if [[ "$ext" =~ ^(png|jpg|jpeg|gif|webp|bmp|svg|ico|tiff|tif)$ ]]; then
    # show_image.py uses `kitty @` remote control + `kitten icat`. Skip the
    # uv-run cold start when kitty isn't on PATH — there's nothing to display to.
    if command -v kitty >/dev/null 2>&1; then
        # Errors suppressed so a non-kitty parent terminal doesn't block the Read result
        uv run "$show_image_script" "$file_path" 2>/dev/null || true
    fi
fi
