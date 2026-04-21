---
name: re-read
description: >
  Post-edit audit checklist applied to the ±30-line region after Edit/Write
  tool calls. TRIGGER only when the re-read-after-edit hook reason names
  this skill.
compatibility: Claude Code
---

# Re-Read After Edit

Use the Read tool on the ±30 lines around the edit, and audit against the checklist for the file type below. Extend the window when more context helps. Chain Read, Grep, or Glob across referenced files and modules for cross-file checks like `Hallucinated references` — a single Read is not a ceiling.

## Documentation

- **Contradictions** — new statements contradicting unchanged surrounding text or earlier sections in the same file.
- **Hallucinated references** — documentation describing APIs, CLI flags, commands, config keys, modules, or tools that may not actually exist; uncommon libraries and niche flags are highest risk.
- **Stale references** — file paths, architecture documents, or quoted code snippets that no longer match what they reference.
- **Tonal drift in new content** — new lines diverging from unchanged siblings in length or rhetorical strength; flag editorial framing ("useful for X", "critical for", "recommended for"), audience-guidance, selling language, over-explanation, justifying parentheticals ("obvious thing (long explanation defending it)").
- **Defensive caveats** — paragraphs warning about failure modes the reader isn't hitting; flag "Why not X? Because…" preemptive Q&A framings, "Caveats:"/"Gotchas:" lists anticipating hypothetical mistakes, parenthetical warnings about edge cases of adjacent machinery that the documented pattern doesn't depend on.
- **Audience mismatch** — guidance shaped for a reader different from the file's actual consumer; flag interactive-human cues (keyboard shortcuts, walkthrough framing, "open a terminal") in agent-facing or non-interactive reference docs, author-local artifacts (absolute home paths, personal usernames, machine-specific config) in public-facing docs like READMEs, and low-level internals or protocol detail in end-user tutorials.
- **Incident-flavored examples** — concrete details from the writer's current task embedded as canonical triggers in reusable reference docs (checklists, style guides, conventions, architecture notes); flag specific tool names, error strings, filenames, or task-at-hand artifacts that would read as out-of-scope when the doc is consulted outside today's context.
- **Style/convention drift** — list styles, heading levels, formatting patterns, separators, naming, idioms.
- **Over-emphasis** — abuse of **bold**, *italic*, ALL-CAPS not matching siblings' average emphasis strength and format.
- **Inverted phrasing** — fronted conditionals or qualifiers that delay the subject and force the reader to hold context; flag "when X, do Y" where "Y when X" reads more directly.
- **Patch over restructure** — minimal-diff edits where a bigger restructure would improve readability or orderliness; flag bullet appended to a list that should be regrouped, paragraph grown unwieldy, section heading no longer matching its content, content stuck in the wrong section.
- **Positional fit** — new items placed near the edit site rather than next to their thematic siblings.

## Code

- **Contradictions** — new code violating types, invariants, or assumptions established by unchanged surrounding code.
- **Hallucinated references** — code calling APIs, importing symbols, using CLI flags, or reading config keys that may not actually exist; verify uncommon library calls and niche CLI flags against source or docs rather than training-data recall.
- **Comment/code mismatch** — comments or docstrings that no longer describe what the adjacent code actually does.
- **Structural drift in new code** — new code diverging from siblings in defensiveness, abstraction depth, or verbosity; flag try-except/validation not present in adjacent code, premature helper extractions, comments restating logic, over-typed annotations in inferred-type modules, error handling for scenarios that can't happen.
- **Common AI-slop patterns** — defensive programming where unwarranted, fabricated null-coalescing / defaults / type coercion, `hasattr`/`getattr` access hacks, over-validation, silently swallowed errors, band-aid / monkey patches, hard-coded or downstream workarounds, backward-compatibility hacks, dead code and leftovers.
- **Scope creep** — edits beyond what the task requires; flag drive-by renames, unsolicited refactors, and formatting changes mixed into a logic fix.
- **Style/convention drift** — naming conventions, indentation, import order, error-handling patterns, libraries, field optionality, idioms.
- **Debug leftovers** — `print()`, `console.log`, `debugger;`, commented-out trial code, scratch comments.
- **Patch over refactor** — minimal-diff edits where a refactor would improve quality or maintainability; flag logic squeezed into already-overloaded if/else, parameters accreted instead of grouped into a config object, abstractions patched around instead of fixed, boolean flags added to functions that should split.
- **Missed extraction** — new code duplicating logic that already exists elsewhere and could be a shared function.
- **Module placement** — new function/class placed in a convenient-but-unrelated module; flag additions made to the currently-open file rather than the module that owns the concept, or to a catch-all when a new module would fit better.

## Mitigation

- **Issues** — fix proactively in the same turn.
- **Clean** — proceed silently; NEVER narrate the audit or preface your reply with its verdict ("Region clean", "Audit passed").
