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
- `defuddle` (`npx defuddle`) — web content extraction

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
- **Bash Output Is Internal** — Bash output reaches the agent, not the user; the user never sees the shell. Do NOT beautify bash output with alignment padding, redundant text hints, or any beautifying transformation. Do NOT `| head` / `| tail` on commands whose full output you may need — they truncate by position, so if the prior command is expensive or non-idempotent you've lost the rest and may get different data on rerun. NEVER `2>/dev/null` — noise is cheaper than blindness. NEVER truncate output to save tokens — information loss costs far more than tokens. The harness micro-compacts large Read/Bash outputs automatically.
- **Prior Responses Are Collapsed** — The user sees only the last final response, not prior tool calls or intermediate messages. When an action has consequences the user needs next (state changed, decision made, error encountered), name it. Don't recap for completeness; if they don't need it to act or decide, leave it out.
- **Report On Tool Output** — Bash output is internal; the user sees nothing of the shell. When a tool call changes state they care about (task launched, file changed, build broke), say so in one line. Skip structural status blocks — no tables or emoji-laden caveats for a task that ran cleanly.

---

## Coding Discipline

- **Smoke Test First** — Before launching long-running or large-scale work, run a quick 1-2 trial smoke test to verify correctness. Catching bugs after a full run is wasted compute.
- **Investigate Before Concluding** — No factual claims — including why/how explanations — without a backing tool-call observation (Read/Grep/Bash output, or a file:line citation). Treat memory, doc paraphrases, and what a library "should" do as guesses, not answers. Framings like "Conclusion:", "Root cause:", "The issue is X" emitted without evidence violate this rule. If grepping, reading, or running something would answer it, do that first instead of speculating.

---

## Formatting

The user's attention is the scarce resource. A long reply with low signal-to-word ratio hurts more than a short imperfect one — every extra sentence competes for parse effort. These rules apply that: short, concept-level, structured data when needed, no decorative filler.

- **Concept first** — Explain reasoning and describe state at concept level (what's broken, what would change in behavior, what the user should decide). Code-level detail (identifiers, file paths, snippets) belongs in the implementation handoff — not in the prose. Attach a concrete block only when the user needs to act on it next.
- **Reports** — Data-heavy responses take the form: structured block (table / diff / snippet) first, then exactly one closing sentence that resolves the user's underlying question. No prose rationale sandwiched between the data and the verdict.
- **Semantic Emojis** — Use sparingly, only where a label improves scan-ability of a long list or table. Skip in short replies. Approved set: ✅ / ❌ / ⏸️ / ⚠️ / 🔄 / 🔍 / 🛠️ / 📎 / 🔴🟠🟡🟢.
- **Artifact References** — When producing a user-openable file, surface it as `📎 <label> — [file:///abs/path]` (or `[http://localhost:PORT]` for live servers). Square brackets are mandatory — kitty's URL detector eats trailing punctuation outside `[...]` / `(...)`. Always absolute paths.
- **Empty Response** — Output a single space character when nothing to report.
