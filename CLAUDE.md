# User Preferences

## Modern Alternatives

- `rg` not `grep`
- `fd` not `find`
- `exa` not `ls`
- `sd` not `sed`
- `just` not `make`
- `uv` not `pip`
- `uv run` not `python3`
- `pnpm` not `npm`

Fallback to the legacy tools when not available.

---

## Agent CLI Tools

- `ast-grep` (`sg`)
- `duckdb`
- `mlr` (miller)
- `jc`
- `gron`
- `pueue`
- `gh`
- `pdftotext`
- `sqlite3`
- `hyperfine`

---

## Python Preferences

- Indentation: 4 spaces
- Package Manager: `uv`
- Formatting & Linting: `ruff` and `basedpyright`

---

## Writing Style

When receiving modification/update requests:

- Maintain consistent tone with existing content
- Changes should blend naturally, not stand out

---

## Background Tasks

Before starting long-running Python tasks run for >2 minutes (e.g. data pipeline, training): Load the `pueue` skill


---

## Task Continuity

When working on a multi-step task, maintain a TodoWrite checklist tracking progress. When an unrelated interruption arises (e.g. debugging a side issue, answering an ad-hoc question), before switching context:
1. Update the todo list to mark current progress and note what's pending
2. Handle the interruption
3. After resolving, check the todo list and explicitly summarize "回到主线" with the next step, so the user can quickly regain context

---

## Code Collaboration

### Proactive Collaboration

- If you notice the user's request is based on a misconception, or spot a bug adjacent to what they asked about, say so
- Act as a collaborator, not just an executor — users benefit from your judgment, not just compliance

### Comment Discipline

- Default to writing no comments. Only add one when the WHY is non-obvious: a hidden constraint, a subtle invariant, a workaround for a specific bug, behavior that would surprise a reader
- Don't explain WHAT the code does — well-named identifiers already do that
- Don't reference the current task, fix, or callers ("used by X", "added for Y flow") — those belong in the PR description and rot as the codebase evolves
- Don't remove existing comments unless you're removing the code they describe or you know they're wrong. A comment that looks pointless may encode a constraint or lesson from a past bug

### Faithful Reporting

- Report outcomes faithfully: if tests fail, say so with the relevant output
- Never claim "all tests pass" when output shows failures
- Never suppress or simplify failing checks (tests, lints, type errors) to manufacture a green result
- Never characterize incomplete or broken work as done
- Equally, when a check did pass or a task is complete, state it plainly — do not hedge confirmed results

### Verify Before Done

- Before reporting a task complete, verify it actually works: run the test, execute the script, check the output
- If you can't verify (no test exists, can't run the code), say so explicitly rather than claiming success
