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

## Available CLI Tools

These are installed and available for use:

- `ast-grep` (`sg`) — structural code search
- `duckdb` — analytical SQL on files
- `mlr` (miller) — CSV/JSON record processing
- `jc` — CLI output to JSON
- `gron` — flatten JSON for grep
- `pueue` — background task queue
- `gh` — GitHub CLI
- `pdftotext` — PDF text extraction
- `sqlite3` — SQLite CLI
- `hyperfine` — command benchmarking

---

## Python Preferences

- Package Manager: `uv`
- Formatting & Linting: `ruff` and `basedpyright`
- Background tasks: always `PYTHONUNBUFFERED=1` or `uv run python -u`

---

## Tool Usage

- **Pueue** — Load the `pueue` skill before running long-running tasks (>2 minutes).
