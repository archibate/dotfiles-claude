#!/usr/bin/bash
set -euo pipefail

source "$(dirname "$0")/lib/bypass.sh"
source "$(dirname "$0")/lib/emit.sh"
source "$(dirname "$0")/lib/read_input.sh"

read_bash_command
bypass_check BYPASS_CAT_WRITE

# Detect cat with heredoc AND file redirection
# Pattern: cat << EOF > file, cat > file << EOF, cat << EOF | tee file
# Only match cat at command position (start of line or after && ; |), not inside strings
if ! echo "$command" | grep -qP '(^|&&|;|\|)\s*cat\b.*<<'; then
    exit 0
fi

# Check for file output redirection (>, >>, or | tee) on the same line as cat
if ! echo "$command" | grep -qP '(^|&&|;|\|)\s*cat\b.*(>\s*\S|>>\s*\S|\|\s*tee\b)'; then
    exit 0
fi

# Implicit bypass for git commit (heredoc used for commit message)
if echo "$command" | grep -qE '\bgit\s+commit\b'; then
    exit 0
fi

# Extract target file path for helpful error message
# Stop at first space, <, |, or newline to avoid capturing heredoc marker
file_path=$(echo "$command" | grep -oE '>\s*[^<>|& ]+' | head -1 | sed 's/^>\s*//' | tr -d "'" || true)

if [ -n "$file_path" ]; then
    example=$(printf '  Write("%s", <content>)' "$file_path")
    reason="Use Write tool instead of cat heredoc for file writes.
${example}
If you have legitimate reason, add comment \`# BYPASS_CAT_WRITE\` before the first line of command."
else
    reason='Use Write tool instead of cat heredoc for file writes.
If you have legitimate reason, add comment `# BYPASS_CAT_WRITE` before the first line of command.'
fi

emit_pre_tool_deny "$reason"
