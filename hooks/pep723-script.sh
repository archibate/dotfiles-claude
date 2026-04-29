#!/usr/bin/bash
set -euo pipefail

source "$(dirname "$0")/lib/read_input.sh"

read_file_path

# Only check .py files
if [[ "$file_path" != *.py ]]; then
    exit 0
fi

content=$(jq -r '.tool_input.content // ""' <<< "$input")

# Only check files that have a shebang (scripts, not modules)
if [[ "$content" != "#!"* ]]; then
    exit 0
fi

# Only check when uv is available
if ! command -v uv >/dev/null 2>&1; then
    exit 0
fi

# Skip inside an active conda env — the interpreter is managed by conda, not uv scripts.
if [ -n "${CONDA_PREFIX:-}" ]; then
    exit 0
fi

# Skip inside an active virtualenv — the interpreter is managed by the venv, not uv scripts.
if [ -n "${VIRTUAL_ENV:-}" ]; then
    exit 0
fi

expected_shebang="#!/usr/bin/env -S uv run --script"
first_line=$(printf '%s' "$content" | head -1)

source "$(dirname "$0")/lib/emit.sh"

# Check 1: shebang must use uv run --script
if [[ "$first_line" != "$expected_shebang" ]]; then
    emit_post_tool_context "Fix shebang to \`#!/usr/bin/env -S uv run --script\` (found: ${first_line}) and add a PEP 723 metadata block."
    exit 0
fi

# Check 2: PEP 723 metadata block must exist
if ! printf '%s' "$content" | grep -qF '# /// script'; then
    emit_post_tool_context 'Add PEP 723 inline metadata block after the shebang:
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "package-name",
# ]
# ///'
    exit 0
fi

exit 0
