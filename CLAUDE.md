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
