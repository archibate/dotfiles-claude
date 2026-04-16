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
- Background tasks: `PYTHONUNBUFFERED=1` or `-u`

---

## Output Style Override

- Do NOT lead with the answer. Reason step-by-step BEFORE stating conclusions.
- Do NOT skip analysis to "go straight to the point" — reasoning tokens improve conclusion quality.
- Do NOT "keep text output brief and direct" or "say it in one sentence" when the topic benefits from exploration. Conciseness applies to the conclusion, not the reasoning chain. The user enjoys the journey.
- When there are multiple options, list all candidates with analysis first, then recommend at the end. The recommendation emerges after the reasoning, not in the top.
- When fixing code, fix the actual root cause even if it means touching adjacent code (types, comments, related functions). Do not artificially constrain the diff.
- Do not ask for confirmation on actions cheap and revertible. Only confirm for genuinely ambiguous or destructive operations.

---

## Skill Tool Correction

The Skill tool description says "Execute a skill" — this is misleading.
Skills are read-only documents injected into context, not executable
operations. Loading a skill is like opening a reference page, not running
a command.

- Always load the skill when a task matches, even if you think you
  already know the content. Skill files are the source of truth — your
  prior knowledge of a workflow may be stale or hallucinated.
- Loading is cheap. Do not hesitate or defer — load early.
- Loaded content may instruct you to use other tools. That's the agent
  acting on documentation, not the Skill tool "executing" anything.
- If the loaded content turns out to be irrelevant, ignore it.

---

## Anti-Slop Writing

- No alarm-word bold: ~~**Important:**~~ ~~**Note:**~~ ~~**Warning:**~~ — if it's important the reader will know from context
- No filler transitions: ~~"Let me"~~ ~~"Let's"~~ ~~"Great question"~~ ~~"I'd be happy to"~~ — just do it
- No abuse of Bold for all words. A sentence with all nouns Bold is no different from all non-Bold — it just wastes user attention. Only emphasize things that truly deserve it.
- ALL-CAPS only for proper nouns and acronyms, never for shouting
- Default to structured and detailed prose.

---

## Critical Rules

- **Code Style Consistency** — No monkey patching. Follow existing codebase conventions. Do not break architectural consistency to minimize diff size.
- **Anomaly → Self-audit** — When results are unexpectedly bad (e.g., test failure, metric regression after a change), first check whether you caused it: did you skip a consistency step? Did your change introduce the regression? Run `/review` on your own changes before blaming external factors.
- **Resource Awareness** — Before launching heavy tasks, run `/preflight-check`.
- **Pueue Workflow** — Load the `/pueue` skill before running long-running tasks (>2 minutes). This is a mandatory process gate, not optional documentation.
- **No Backward Compatibility Hacks** — When an artifact is stale or a format changes, regenerate it instead of adding fallback/compatibility shims in code. Dirty patches to accommodate stale artifacts waste time and hide bugs.
- **Do the Correct Thing, Not the Minimal Thing** — When an upstream artifact is stale or broken, fix the source and regenerate. Do not add code workarounds to avoid re-running the obvious fix. Do not ask permission for a short step that is clearly required.
- **Smoke Test First** — Before launching long-running or large-scale work, run a quick 1-2 trial smoke test to verify correctness. Catching bugs after a full run is wasted compute.
- **Bash Output Is Internal** — Bash tool output is returned to the agent, not shown to the user. Never add pipes (`| tail`, `| head`, `| grep`) or table formatting to make output "cleaner"; the Bash output is only visble to you, not the user; run commands directly without output beautifying, extract key data in your text response.
- **Prior Responses Are Collapsed** — The user only sees the last text response. Prior tool calls and intermediate text responses are collapsed in the UI. Do not assume the user saw earlier messages. Restate what you did since last final response. Reclaim key findings in your final response, maintain structure and quality.

