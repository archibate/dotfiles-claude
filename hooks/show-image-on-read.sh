#!/usr/bin/bash
# PostToolUse hook: display images in Kitty terminal after Read tool on image files
set -euo pipefail

# Resolve repo root relative to this hook script (hooks/ and skills/ share same parent)
repo_root=$(dirname "$(dirname "$(readlink -f "$0")")")
show_image_script="$repo_root/skills/show-image/scripts/show_image.py"

input=$(cat)
file=$(echo "$input" | jq -r '.tool_input.file_path // empty')

# Skip if no file path
[ -n "$file" ] || exit 0

# Get extension and check if it's an image
ext=$(echo "$file" | sed 's/.*\.//' | tr '[:upper:]' '[:lower:]')

if [[ "$ext" =~ ^(png|jpg|jpeg|gif|webp|bmp|svg|ico|tiff|tif)$ ]]; then
    # Run show-image script (silently - errors go to /dev/null)
    uv run "$show_image_script" "$file" 2>/dev/null || true
fi
