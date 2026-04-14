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

## Critical Rules

- **Git** — Never `commit --amend`. Always create new commits.
- **Code Style Consistency** — No monkey patching. Follow existing codebase conventions. Do not break architectural consistency to minimize diff size.
- **Re-read After Editing Docs** — After updating any documentation file (CLAUDE.md, skill docs, references), re-read the entire file to catch stale content, numbering errors, contradictions, and duplication introduced by the edit.
- **Anomaly → Self-audit** — When results are unexpectedly bad (e.g., test failure, metric regression after a change), first check whether you caused it: did you skip a consistency step? Did your change introduce the regression? Run `/review` on your own changes before blaming external factors.
- **Resource Awareness** — Before launching heavy tasks, run `/preflight-check`.
- **Pueue** — Load the `/pueue` skill before running long-running tasks (>2 minutes).
- **No Backward Compatibility Hacks** — When an artifact is stale or a format changes, regenerate it instead of adding fallback/compatibility shims in code. Dirty patches to accommodate stale artifacts waste time and hide bugs.
- **Do the Correct Thing, Not the Minimal Thing** — When an upstream artifact is stale or broken, fix the source and regenerate. Do not add code workarounds to avoid re-running the obvious fix. Do not ask permission for a short step that is clearly required.
- **Smoke Test First** — Before launching long-running or large-scale work, run a quick 1-2 trial smoke test to verify correctness. Catching bugs after a full run is wasted compute.
- **Explore Model** — Explore defaults to Haiku, not inherited from the main agent. Always spawn Explore subagents with `model: "sonnet"` to balance hallucination risk and cost.
- **Verify Explore Results** — After receiving Explore subagent results, verify key claims (file paths, function signatures, line numbers) with a direct Read or Grep before acting on them. Do not trust Explore output blindly.

---

## Cache Hygiene

The prompt cache has a 5-minute TTL. A cache miss (re-write) costs 1.25× vs 0.1× for a hit — keeping the cache warm saves ~1.15P per avoided miss.

**Turn discipline:**
- When a Bash command or agent is auto-backgrounded, briefly acknowledge it and **end your response**. Do not immediately read the output file or poll for completion.
- Never poll a background task in a loop without ending your response between iterations. Repeated blocking reads (TaskOutput, Read, tail) within a single turn hold the conversation hostage and bust the cache.
- On `/loop` keep-alive boundaries, it is OK to quickly peek progress of currently running tasks (a single non-blocking read), then end your response. Do not spiral into repeated polling.

**Timeout caps:**
- Prefer `run_in_background: true` for Bash commands or agents expected to exceed 2 minutes, so the turn unblocks immediately.
- Never pass `timeout` > 240000 (4 min) to TaskOutput. Use `block: false` for a quick non-blocking peek, or use the default 30s timeout. If the task isn't done, end your response and check again on the next loop boundary.

**Keep-alive loop:**
- When launching background work expected to idle the main thread for more than 5 minutes, proactively start a keep-alive loop (`/loop 5m Cache keep-alive. If background tasks are running, peek progress briefly (non-blocking). Otherwise reply "ok".`) to keep the cache warm.
- If a keep-alive loop runs for 10 consecutive iterations with no real user interaction and no background tasks to monitor, stop it (`CronDelete`). As long as there are running background tasks, the loop remains justified.
