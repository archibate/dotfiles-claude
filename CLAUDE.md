# Global Behavior Rules

## Available CLI Tools

These are installed and available for use:

- `rg` not `grep`
- `fd` not `find`
- `exa` not `ls`
- `sd` not `sed`
- `just` not `make`
- `uv` not `pip`
- `uv run` not `python3`
- `pnpm` not `npm`
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

## Output Style Override

- Do NOT lead with the answer. Reason step-by-step BEFORE stating conclusions.
- Do NOT skip analysis to "go straight to the point" — reasoning tokens improve conclusion quality.
- Conciseness applies to the conclusion, not the reasoning chain.
- When fixing code, fix the actual root cause even if it means touching adjacent code (types, comments, related functions). Do not artificially constrain the diff.
- Do not ask for confirmation on actions I've already authorized via permissions or CLAUDE.md. Only confirm for genuinely ambiguous or destructive operations.

---

## Critical Rules

- **Git** — Never `commit --amend`. Always create new commits.
- **Code Style Consistency** — No monkey patching. Follow existing codebase conventions. Do not break architectural consistency to minimize diff size.
- **Re-read After Editing Docs** — After updating any documentation file (CLAUDE.md, skill docs, references), re-read the entire file to catch stale content, numbering errors, contradictions, and duplication introduced by the edit.
- **Anomaly → Self-audit** — When results are unexpectedly bad (e.g., test failure, metric regression after a change), first check whether you caused it: did you skip a consistency step? Did your change introduce the regression? Run `/review` on your own changes before blaming external factors.
- **Resource Awareness** — Before launching heavy tasks, run `/preflight-check`.
- **Pueue Workflow** — Load the `/pueue` skill before running long-running tasks (>2 minutes). This is a mandatory process gate, not optional documentation.
- **No Backward Compatibility Hacks** — When an artifact is stale or a format changes, regenerate it instead of adding fallback/compatibility shims in code. Dirty patches to accommodate stale artifacts waste time and hide bugs.
- **Do the Correct Thing, Not the Minimal Thing** — When an upstream artifact is stale or broken, fix the source and regenerate. Do not add code workarounds to avoid re-running the obvious fix. Do not ask permission for a short step that is clearly required.
- **Smoke Test First** — Before launching long-running or large-scale work, run a quick 1-2 trial smoke test to verify correctness. Catching bugs after a full run is wasted compute.
- **Explore Model** — Explore defaults to Haiku, not inherited from the main agent. Always spawn Explore subagents with `model: "sonnet"` to balance hallucination risk and cost.
- **Verify Explore Results** — After receiving Explore subagent results, verify key claims (file paths, function signatures, line numbers) with a direct Read or Grep before acting on them. Do not trust Explore output blindly.
- **Cache Keep-Alive** — After launching a background agent or task (`run_in_background: true`), load `/cache-hygiene` and follow its keep-alive protocol.

