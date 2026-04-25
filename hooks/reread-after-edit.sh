#!/usr/bin/bash
# PostToolUse hook: after editing a file, inject a re-read reminder with inline checklist.
# Doc files and code files get different checklists.
set -euo pipefail

source "$(dirname "$0")/lib/emit.sh"
source "$(dirname "$0")/lib/read_input.sh"

read_file_path

case "${file_path,,}" in
    *.md|*.markdown|*.rst|*.txt|*.adoc|*.org|*.tex)
        kind="DOC"
        ;;
    *.py|*.pyi|*.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs|*.go|*.rs|*.c|*.cc|*.cpp|*.cxx|*.h|*.hpp|*.java|*.kt|*.scala|*.rb|*.php|*.sh|*.bash|*.zsh|*.fish|*.lua|*.vim|*.el|*.clj|*.ex|*.exs|*.swift|*.m|*.mm|*.r|*.sql|*.html|*.htm|*.css|*.scss|*.sass|*.less|*.vue|*.svelte|*.json|*.yaml|*.yml|*.toml|*.ini|*.cfg|*.dockerfile|dockerfile|makefile|justfile)
        kind="CODE"
        ;;
    *)
        kind="DOC"
        ;;
esac

if [[ "${kind}" == "DOC" ]]; then
    emit_post_tool_context "Re-read ${file_path} (±30 lines) — DOC audit, walk explicitly through:
- Over-emphasis: bold/emoji/🆕/ALL-CAPS density vs surrounding lines?
- Tonal drift in new content: matches sibling rhetorical strength and length?
- Justifying asides: parentheticals defending obvious claims?
- Defensive caveats: warnings about failure modes the reader isn't hitting?
- Hallucinated refs: uncommon API/flag/symbol/command verified against source?
- Stale references: file paths or quoted snippets still match what they reference?
- Audience mismatch: agent-facing doc has interactive-human cues, or vice versa?
- Style/convention drift: list/heading/separator/emoji conventions consistent?
- Patch over restructure: bigger regroup needed instead of minimal-diff append?
- Positional fit: new items near edit site rather than thematic siblings?
Silent fix per item. Do NOT narrate — no 'Region clean' or audit-verdict preface."
else
    emit_post_tool_context "Re-read ${file_path} (±30 lines) — CODE audit, walk explicitly through:
- Contradictions: new code violates types/invariants/assumptions in unchanged surrounding code?
- Comment/code mismatch: docstring/comment still describes the actual behavior?
- Structural drift: defensiveness/abstraction depth/verbosity matches adjacent code?
- AI-slop defensive programming: unwarranted try-except/null-coalescing/hasattr/getattr/over-validation?
- AI-slop band-aid patches: hardcoded workarounds, backward-compat shims, monkey patches, swallowed errors, dead leftovers?
- Hallucinated refs: uncommon library API/CLI flag/config key verified against source/docs?
- Scope creep: drive-by renames, unsolicited refactors, formatting mixed into logic fix?
- Style/convention drift: naming/indentation/import order/error-handling/idioms consistent?
- Debug leftovers: print()/console.log/debugger;/commented-out trial code/scratch comments?
- Patch over refactor: logic squeezed into overloaded if-else, parameters accreted instead of grouped?
- Missed extraction: new code duplicates logic that already exists and could be shared?
- Module placement: new function/class in convenient-but-unrelated file vs the module that owns the concept?
Silent fix per item. Do NOT narrate — no 'Region clean' or audit-verdict preface."
fi
