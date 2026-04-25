#!/usr/bin/bash
# Stop hook: spawn a fresh-eye audit subagent over all files edited this turn.
# Uses asyncRewake — exit 2 wakes the main agent with fix instructions; exit 0
# stays silent. Recursion guard: when this hook fires inside the audit subagent
# itself, CLAUDE_AUDIT_SUBAGENT=1 is set in the env, and we exit early.
set -euo pipefail

# Recursion guard — the audit subagent itself triggers its own Stop hook
if [[ "${CLAUDE_AUDIT_SUBAGENT:-}" == "1" ]]; then
    exit 0
fi

input=$(cat /dev/stdin)
session_id=$(jq -r '.session_id // empty' <<< "${input}")

[ -z "${session_id}" ] && exit 0

queue_dir="/tmp/claude-audit-queue"
queue_file="${queue_dir}/${session_id}.txt"

[ -f "${queue_file}" ] || exit 0

# Drain the queue: dedup paths, then clear so next turn starts fresh
files=$(sort -u "${queue_file}")
rm -f "${queue_file}"

[ -z "${files}" ] && exit 0

file_list=$(echo "${files}" | sed 's|^|- |')

prompt="You are a fresh-eye audit subagent. The following files were edited in the most recent conversation turn:

${file_list}

For each file:
  1. Classify by basename — DOC if ext is .md/.markdown/.rst/.txt/.adoc/.org/.tex (but CMakeLists.txt is CODE); CODE if ext is .py/.js/.ts/.go/.rs/.sh/.cmake/.json/.yaml or basename is Dockerfile/Makefile/justfile/.gitignore etc; OTHER for anything else (skip OTHER files).
  2. Read it, focusing on recent changes (typically near the bottom or any clearly newer-looking section).
  3. Use Grep/Glob if needed to verify cross-file claims (e.g. for CODE: check whether a helper already exists elsewhere — Missed extraction; verify Module placement by Glob over similar files. For DOC: check whether a referenced file path actually exists).
  4. Walk through this checklist:

DOC checklist:
- Contradictions: new statements contradict unchanged surrounding text or earlier sections?
- Over-emphasis: bold/emoji/🆕/ALL-CAPS density vs surrounding lines?
- Tonal drift in new content: matches sibling rhetorical strength and length?
- Justifying asides: parentheticals defending obvious claims?
- Defensive caveats: warnings about failure modes the reader isn't hitting?
- Hallucinated refs: uncommon API/flag/symbol/command verified against source?
- Stale references: file paths or quoted snippets still match what they reference?
- Audience mismatch: agent-facing doc has interactive-human cues, or vice versa?
- Incident-flavored examples: concrete details from current task embedded as canonical triggers in reusable docs?
- Style/convention drift: list/heading/separator/emoji conventions consistent?
- Inverted phrasing: fronted conditionals or qualifiers that delay the subject?
- Patch over restructure: bigger regroup needed instead of minimal-diff append?
- Positional fit: new items near edit site rather than thematic siblings?

CODE checklist:
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

Default to CLEAN. Only flag HIGH-confidence issues a careful future reader would actually notice. Do NOT flag stylistic preferences, hypothetical concerns, or items where the existing code has the same pattern (i.e. only flag if the issue is novel to the recent change).

Output exactly one of:
- CLEAN
- FIXES:
  <file_path>:
    - <one-line specific fix instruction>
    - ...

Output the verdict only, no narration, no preamble."

verdict=$(CLAUDE_AUDIT_SUBAGENT=1 claude -p "${prompt}" \
    --model sonnet \
    --allowedTools Read,Grep,Glob \
    --permission-mode bypassPermissions \
    --max-budget-usd 0.20 \
    --output-format text) || exit 0

if [[ "${verdict}" == CLEAN* ]] || [[ -z "${verdict}" ]]; then
    exit 0
fi

echo "${verdict}"
exit 2
