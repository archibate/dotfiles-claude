#!/usr/bin/bash
# PostToolUse hook: after WebSearch, remind to fetch interesting links.
# Search results are titles + URLs + synthesized summary — not full page content.
set -euo pipefail

input=$(cat)
source "$(dirname "$0")/lib/emit.sh"

# Skip if the search returned no results — nothing to follow up on.
result_count=$(echo "$input" | jq -r '[.tool_response.results[]?] | length')
[ "$result_count" -gt 0 ] || exit 0

emit_post_tool_context 'WebSearch returns result titles and URLs plus a short synthesized summary — not the full page content. To actually read a result that matters, use WebFetch; if WebFetch is truncated or refused, fall back to the /read-url skill. Never cite a WebSearch result as a source without reading it.'
