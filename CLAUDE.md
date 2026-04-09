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

- Package Manager: `uv`
- Formatting & Linting: `ruff` and `basedpyright`

---

## Background Tasks

Before starting long-running Python tasks run for >2 minutes (e.g. data pipeline, training): Load the `pueue` skill

---

## Task Continuity

When working on a multi-step task, maintain a TodoWrite checklist tracking progress. When an unrelated interruption arises (e.g. debugging a side issue, answering an ad-hoc question), before switching context:
1. Update the todo list to mark current progress and note what's pending
2. Handle the interruption
3. After resolving, check the todo list and explicitly summarize "back to main topic" with the next step, so the user can quickly regain context
