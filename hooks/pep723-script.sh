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
    printf 'Fix shebang to `#!/usr/bin/env -S uv run --script` (found: %s) and add a PEP 723 metadata block.\n' "$first_line" >&2
    exit 2
fi

# Check 2: PEP 723 metadata block must exist
if ! printf '%s' "$content" | grep -qF '# /// script'; then
    printf 'Add PEP 723 inline metadata block after the shebang:\n# /// script\n# requires-python = ">=3.11"\n# dependencies = [\n#   "package-name",\n# ]\n# ///\n' >&2
    exit 2
fi

exit 0
