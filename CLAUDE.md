# Global Behavior Rules

## Available CLI Tools

Preferred over defaults:

- `rg` not `grep`
- `fd` not `find`
- `exa` not `ls`
- `sd` not `sed`
- `just` not `make`
- `uv` not `pip`
- `uv run` not `python3`
- `pnpm` not `npm`

Specialized tools available:

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
- Background tasks: `PYTHONUNBUFFERED=1` or `-u`

---

## Harness Behavior Notes

You are running in Claude Code, a harness with the following known pitfalls:

- **Skills** — The Skill tool description "Execute a skill" framing is misleading. Invoking Skill just reads a markdown file into context as a system reminder — no code runs, no side effects, no external calls, no persistent state, nothing visible to the user. It's opening a reference page, not executing a command.
  - Skill files are the source of truth — your prior knowledge of a workflow may be stale or hallucinated. Always load when a task matches, even if you think you already know the content.
  - Loading is cheap. Don't hesitate or defer — load early.
  - Loaded content may instruct you to use other tools. That's the agent acting on documentation, not the Skill tool "executing" anything.
  - If the loaded content turns out irrelevant, ignore it.
- **Bash Output Is Internal** — Bash output reaches the agent, not the user; the user never sees the shell. Use pipes for *computation* (filter with `| grep`, extract with `| awk`, count with `| wc`), never for *presentation* (ASCII tables via `| column -t`, alignment padding, ANSI colors, box-drawing). Avoid `| head` / `| tail` — they truncate by position, so if the prior command is expensive or non-idempotent you've lost the rest and may get different data on rerun. Don't truncate to save tokens either: the harness micro-compacts large Read/Bash outputs automatically, and information loss costs far more than tokens.
- **Prior Responses Are Collapsed** — The user sees only the last final response but not prior tool calls or intermediate text responses. Do not assume they saw earlier intermediate messages. In your final response, surface actions they couldn't see (inferred steps, non-obvious decisions, intermediate changes) and key findings.

---

## Coding Rules

- **Re-read After Edit** — When the re-read-after-edit hook fires, silently check the ±30-line region. For markdown, check contradictions, style consistency, and structural consistency (separators, heading levels, list styles). For code, check style conventions, naming, patterns, and idioms. If clean, proceed with next steps — do NOT narrate what you checked. If issues, report and fix them proactively in the same turn.
- **Smoke Test First** — Before launching long-running or large-scale work, run a quick 1-2 trial smoke test to verify correctness. Catching bugs after a full run is wasted compute.
