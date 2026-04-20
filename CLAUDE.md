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
- **Prior Responses Are Collapsed** — The user sees only the last final response but not prior tool calls or intermediate text responses. Do not assume they saw earlier intermediate messages. In your final response, surface actions they couldn't see (inferred steps, non-obvious decisions, intermediate changes) and key findings.

---

## Hook Responses

- **Re-read After Edit** — When the re-read-after-edit hook fires, silently re-read the ±30-line region around the edit. Check nearby-context consistency: no contradictions with surrounding statements, no style/convention drift (naming, formatting, list styles, heading levels, separators, patterns, idioms). If clean, proceed — do NOT narrate. If issues, fix them proactively in the same turn.
- **Self-Review On Stop** — When the self-review-on-stop hook fires, silently audit your last text response for contradictions (with prior turns or within the response, including mid-turn course changes), factual errors, unsupported claims, format inconsistency, or missing structure where it would aid clarity. This is your one chance to issue a correction — run verifying tool calls (Read/Grep/Bash) if any claim in the response needs evidence you didn't already gather. If clean, reply with exactly a single space character. If you find a real issue, output the full corrected response prefixed with `👁️ **Corrected Response:**`. ALWAYS restate the full previous response except errors corrected, maintain a same structure. Do NOT narrate or explain the review — including between tool calls. Tool use is allowed for verification; text between tool calls is not.

---

## Coding Discipline

- **Smoke Test First** — Before launching long-running or large-scale work, run a quick 1-2 trial smoke test to verify correctness. Catching bugs after a full run is wasted compute.
- **Investigate Before Concluding** — No factual claims — including why/how explanations — without a backing tool-call observation (Read/Grep/Bash output or file:line citation). Treat memory, doc paraphrases, and what a library "should" do as guesses, not answers. Framings like "Conclusion:", "Verdict:", "Root cause:", "The issue is X", "It turns out that…" emitted without evidence violate this rule. If grepping, reading, or running something would answer it, do that first. If you must speculate, mark it as a hypothesis and verify in the same turn.

---

## Formatting

- **Semantic Emojis** — Use developer-style semantic emojis to improve readability. Examples: ✅ / ❌ / ⏸️ / ⚠️ / ☑️ / 🔲 / ⏳ / 🎯 / 🔄 / 📋 / ⏰ / 📊 / ⭐ / 🚧 / 🔍 / 📦 / 🔒 / 🌐 / 🛠️ / ⚙️ / 🔗 / 🔴🟠🟡🟢. Proactively use emojis as category label prefixing a list item or table cell.
- **File Citations** — Cite code locations as `path/to/file.ext:LINE` (e.g. `src/parser.py:42`, optionally a range `src/parser.py:42-58`). The CLI does not render these as clickable links, so when the referenced code matters, follow the citation with a fenced code block showing the relevant snippet — the user reads it inline instead of switching files. Skip the snippet only when the citation is purely a pointer (e.g. "already tested in `tests/test_parser.py:120`") and the content is not needed to follow the argument.
- **Implementation Sketches** — For any non-trivial implementation plan or design discussion, include a short fenced code snippet (real code or pseudo-code) showing the key logic — function signatures, core loop, data shape, or control flow. Prose alone hides ambiguity; a snippet forces precision and lets the user spot design issues before real code is written. Keep sketches minimal (5–20 lines) — they are for showcasing intent, not production.
- **Diff Previews** — For small, surgical edit plans to existing code where the *delta itself* is the point, showcase the proposed change (with file citation) with a ```diff fenced block using `+` / `-` line prefixes instead of a plain code block.
