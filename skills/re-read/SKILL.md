---
name: re-read
description: >
  Post-edit audit checklist applied to the ±30-line region after Edit/Write
  tool calls. TRIGGER only when the re-read-after-edit hook reason names
  this skill.
compatibility: Claude Code
---

# Re-Read After Edit

Check the ±30 lines around the edit using the checklist matching the file type:

## Documentation

- **Contradictions** — new statements contradicting unchanged surrounding text or earlier sections in the same file.
- **Style/convention drift** — list styles, heading levels, formatting patterns, separators, naming, idioms.
- **Tonal drift in new content** — new lines diverging from unchanged siblings in length or rhetorical strength; flag editorial framing ("useful for X", "critical for", "recommended for"), audience-guidance, selling language, over-explanation, justifying parentheticals ("obvious thing (long explanation defending it)").
- **Over-emphasis** — abuse of **bold**, *italic*, ALL-CAPS not matching siblings' average emphasis strength and format.
- **Patch over restructure** — minimal-diff edits where a bigger restructure would improve readability or orderliness; flag bullet appended to a list that should be regrouped, paragraph grown unwieldy, section heading no longer matching its content, content stuck in the wrong section.
- **Inverted phrasing** — fronted conditionals or qualifiers that delay the subject and force the reader to hold context; flag "when X, do Y" where "Y when X" reads more directly.
- **Stale references** — file paths, architecture documents, or quoted code snippets that no longer match what they reference.

## Code

- **Contradictions** — new code violating types, invariants, or assumptions established by unchanged surrounding code.
- **Style/convention drift** — naming conventions, indentation, import order, error-handling patterns, libraries, field optionality, idioms.
- **Structural drift in new code** — new code diverging from siblings in defensiveness, abstraction depth, or verbosity; flag try-except/validation not present in adjacent code, premature helper extractions, comments restating logic, over-typed annotations in inferred-type modules, error handling for scenarios that can't happen.
- **Common AI-slop patterns** — defensive programming where unwarranted, fabricated null-coalescing / defaults / type coercion, `hasattr`/`getattr` access hacks, over-validation, silently swallowed errors, band-aid / monkey patches, hard-coded or downstream workarounds, backward-compatibility hacks, dead code and leftovers.
- **Patch over refactor** — minimal-diff edits where a refactor would improve quality or maintainability; flag logic squeezed into already-overloaded if/else, parameters accreted instead of grouped into a config object, abstractions patched around instead of fixed, boolean flags added to functions that should split.
- **Debug leftovers** — `print()`, `console.log`, `debugger;`, commented-out trial code, scratch comments.
- **Comment/code mismatch** — comments or docstrings that no longer describe what the adjacent code actually does.

## Mitigation

- **Issues** — fix proactively in the same turn.
- **Clean** — proceed silently; NEVER narrate the audit or preface your reply with its verdict ("Region clean", "Audit passed").
