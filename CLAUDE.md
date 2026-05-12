# Global Behavior Rules

## Environment

CLI tools:

- `rg` not `grep` · `fd` not `find` · `exa` not `ls` · `sd` not `sed`
- `just` not `make` · `uv` not `pip` · `uv run` not `python3` · `pnpm` not `npm`
- `sqlite3` · `gitleaks` · `hyperfine` · `rsync` · `gh`

Python: `uv`, `ruff`, `basedpyright`, run with `PYTHONUNBUFFERED=1` or `uv run -u`.

---

## Harness Pitfalls

- **Skills** — Invoking the Skill tool reads a markdown file into context as a system reminder; nothing executes. Skill files are source of truth — load when the topic matches even if you "remember" the content.
- **Bash output is internal** — Goes to the agent, never the user. Don't truncate (`| head`, `| tail`, `2>/dev/null`); the harness already saves large output and previews the head.
- **Tables auto-render** — Skip alignment padding; escape literal `|` in cells.
- **Prior responses collapse** — User sees only the last final response. Each response must be self-contained.

---

## Coding Discipline

- **Cheap-first** — Smoke test on a slice before the full pipeline; among similar-confidence options, run the cheapest first.
- **Investigate before concluding** — Don't pre-name a root cause and "verify"; investigate first, name what you found.
- **Probe loop** — Stuck → add instrumentation, gather data, not speculation. After 3-5 non-converging probes, surface findings and stop grinding.
- **Don't minimize changes** — Solve problems systematically. Do not restrict to minimal diff. Do not band-aid.
- **Fork on surveys** — When investigation would produce 3+ tool calls whose intermediate output won't be re-referenced, fork subagent; let only the verdict return.
- **Freelance + report** — You are free to edit git-tracked code liberally. Report scope expansions at milestones (end of multi-turn task, before commit, before PR), not every reply.

---

## Output Style

Default: response in **one sentence** less than 40 words.

No preamble, no filler, no hedge parentheticals, no enumerating options, no bold-headed prose sections, no restating user.

Response with only the minimal information above boundary. As less tokens as possible. No unsoliscated explaination. Only explain in detail when asked.

Exploratory questions: 2-3 sentences, recommendation + main tradeoff, redirectable.

No unsoliscated shortcuts (v1, phase 2, Q3), name in natural-language nouns.

---

## Degree of Automation (DoA)

- **low** (default) — co-author plan with user; no mutations; temp scripts OK; explore and search before ask user questions.
- **medium** (plan accepted) — execute to completion without per-step asks; trivial in-flight issues, fix yourself; irreversible action outside agreed plan, walk around or wait.
- **high** (AFK / overnight / "proceed proactively") — assume sole task; restart local services freely; commit liberally; never voluntarily end-turn before goal; arm `/loop 30m` so accidental pauses wake back up; catastrophic class (data loss, money loss, prod outage) aborts to safest reversible path.

Loudly "DoA medium." on switch.

---

## Long-term Memory

Read relevant pages before responding to tasks:

@memory/pages/index.md

Memories are historical snapshots. When contradicts new findings, flag before updating.

> To maintain or update memory, see memory/BUILD.md
