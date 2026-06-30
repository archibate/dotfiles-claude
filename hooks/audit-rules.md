<!--
Canonical fresh-eye audit rule catalog — SINGLE SOURCE OF TRUTH.

Both auditor wrappers (audit-fresh-eye-claude.md, audit-fresh-eye-codex.md)
carry a `<!-- AUDIT_RULES -->` marker that the assembler in audit-edits.py
replaces with this catalog at spawn time. audit-edits.py also derives
ALL_CATEGORIES by parsing the `- \`TAG\`` tokens below. A new rule is added by
editing only this file. Edit rules here; never copy them into a wrapper.
-->

## DOC categories

- `DOC-contradiction` — new statements contradict unchanged surrounding text, established rules, or other structured sections of the same artifact (frontmatter vs. body, declared interface vs. prose, schema vs. description, sequence in one part vs. sequence in another)
- `DOC-over-emphasis` — bold/emoji/ALL-CAPS density disproportionate to surrounding lines or to the content's load-bearingness
- `DOC-tonal-drift` — new content rhetorical strength/length differs from siblings; flag length when a new/edited table row, bullet, or comment block exceeds its group's Q3 + 1.5·IQR upper fence (skip groups with <5 siblings)
- `DOC-list-parity` — new entry added to a peer enumeration (comma-list, bullet-list, tag set) carries qualifier/parenthetical/rationale absent from existing peers; flag when new-entry word count > 2× median of unchanged peers in the same list
- `DOC-justifying-aside` — an aside defending an obvious claim, OR rationale explaining *why* an instruction/step exists from common knowledge the target reader already holds (teaching first principles in a workflow doc). Signals: `(e.g. ...)`/`(i.e. ...)` glossing a phrase the reader already grasps; a "because/since/so that …" clause justifying a step whose need is self-evident to a capable agent
- `DOC-defensive-caveat` — warning about a failure mode the reader isn't hitting
- `DOC-hallucinated-ref` — uncommon API/flag/symbol/command unverified against source
- `DOC-stale-reference` — file path or quoted snippet no longer matches its target (a catalog deliberately omitting an entry is not stale — only a dangling or factually-wrong ref counts)
- `DOC-duplicates-source` — doc enumerates 2+ concrete identifiers (CLI/function/env-var/path names) that already appear in a source file the doc names or links to; the source is the single point of truth and edits there won't propagate. Suppress when the enumeration is inside a code-block invocation example or when no separate source-of-truth file exists. Cheap detection: (a) diff hunk is in a doc file (`*.md`/`*.rst`/`README*`/`CHANGELOG*`/`*.txt`), (b) added text contains 2+ identifiers separated by commas/slashes/backticks within one sentence or list item, (c) same hunk or its immediate context names a file path that exists in the repo. Confirm by Reading the referenced file's first ~40 lines and checking ≥ 2 of the enumerated identifiers appear there
- `DOC-catalog-narration` — an entry in a top-level catalog/index/overview (recipe table, file inventory, reference index) narrates sub-detail its target owns (rationale, full param semantics, behavior, keep-rules) instead of a terse factual pointer; the entry names what the item IS and points onward, the why/how lives in the referenced code or nested doc
- `DOC-audience-mismatch` — agent-facing doc with interactive-human cues, or vice versa; a single edit can quietly switch register mid-doc
- `DOC-incident-leak` — the doc defends a rule by narrating the incident that produced it (failure showcase, "we saw X happen, so do Y", concrete task details cited as authority) instead of stating the rule in positive imperative form. The incident is conversation residue; the reader just needs the imperative
- `DOC-style-drift` — list/heading/separator/emoji conventions inconsistent with file
- `DOC-inverted-phrasing` — fronted conditional/qualifier delaying the subject
- `DOC-patch-over-restructure` — minimal diff appended where a regroup is needed
- `DOC-positional-fit` — new item near the edit site instead of with thematic siblings

## CODE categories

- `CODE-contradiction` — new code violates types/invariants/assumptions in unchanged surrounding code
- `CODE-comment-mismatch` — docstring/comment no longer describes the actual behavior (a terser comment describing a factually-true subset is NOT a mismatch — flag only when it states something false or omits a load-bearing failure mode)
- `CODE-narrative-comment` — a new comment trivially restates what the adjacent code already says (`i += 1  # increment i`, `# loop over rows` above an obvious loop); the code is ground truth the reader parses directly. KEEP comments carrying what code can't show — a non-obvious decision/rationale (the *why*), a business rule, a gotcha/constraint, or external context
- `CODE-structural-drift` — defensiveness/abstraction depth/verbosity differs from adjacent code
- `CODE-defensive` — unwarranted try/except, null-coalescing, hasattr/getattr, over-validation
- `CODE-bandaid` — a fix shaped by the current incident rather than by the surrounding codebase: hardcoded workaround, backward-compat shim, monkey patch, swallowed error, dead leftover, or code/values that only resolve against the conversation that produced them
- `CODE-hallucinated-ref` — uncommon library API/CLI flag/config key unverified
- `CODE-style-drift` — naming/indentation/import order/error handling/idiom inconsistent
- `CODE-debug-leftover` — `print()`, `console.log`, `debugger;`, commented-out trial code
- `CODE-missed-extraction` — new code duplicates existing logic that could be shared
- `CODE-misplacement` — new function/class in a convenient-but-unrelated file vs the module that owns the concept
- `CODE-sync-not-updated` — a code change creates a parallel-update obligation that wasn't met: an artifact outside this turn's diff (README/`*.md`/`CLAUDE.md`, OpenAPI/JSON schema, locale file, example config, CHANGELOG, mirrored constant or duplicated list in another source file, test or fixture, docstring/comment block in a sibling file, etc.) still reflects the pre-change state, or a new artifact that should have shipped in parallel wasn't added. Only flag artifacts the project actually maintains — don't demand a CHANGELOG, locale entry, or test in a project that has no such convention. For tests specifically, also skip when the change is impractical to test programmatically (UI rendering, real network/IO, timing/concurrency, external services without seams). Catalog exception: when a top-level doc deliberately indexes code or nested docs (recipe table, file inventory, reference index), it is in sync as long as its entries are factually correct — do NOT flag it for omitting sub-detail, or for cataloging fewer items than exist, since a future agent reaches the rest via the entry. The parallel-update obligation applies only to an established doc-code PAIR that canonically restates the detail (a spec section, a docstring), never to a catalog whose entries merely point onward
