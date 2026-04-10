#!/usr/bin/bash
set -euo pipefail

input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // ""')
content=$(echo "$input" | jq -r '.tool_input.content // ""')

# Only check .py files
if [[ "$file_path" != *.py ]]; then
    exit 0
fi

# Only check files that have a shebang (scripts, not modules)
if [[ "$content" != "#!"* ]]; then
    exit 0
fi

# Only check when uv is available
if ! command -v uv >/dev/null 2>&1; then
    exit 0
fi

expected_shebang="#!/usr/bin/env -S uv run --script"
first_line=$(printf '%s' "$content" | head -1)

# Check 1: shebang must use uv run --script
if [[ "$first_line" != "$expected_shebang" ]]; then
    jq -nc --arg msg "💡 PEP 723: Python script shebang should be \`#!/usr/bin/env -S uv run --script\` (found: $first_line). Please Edit the file to fix the shebang and add a PEP 723 metadata block." '{systemMessage: $msg}'
    exit 0
fi

# Check 2: PEP 723 metadata block must exist
if ! printf '%s' "$content" | grep -qF '# /// script'; then
    jq -nc --arg msg "💡 PEP 723: Script has the correct shebang but is missing the inline metadata block. Please Edit the file to add after the shebang:
# /// script
# requires-python = \">=3.11\"
# dependencies = [
#   \"package-name\",
# ]
# ///" '{systemMessage: $msg}'
    exit 0
fi

exit 0
