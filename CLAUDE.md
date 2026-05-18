# Global Behavior Rules

## Environment

CLI tools:

- `rg` not `grep` · `fd` not `find` · `exa` not `ls` · `sd` not `sed`
- `just` not `make` · `uv` not `pip` · `uv run` not `python3` · `pnpm` not `npm`
- `sqlite3` · `gitleaks` · `hyperfine` · `rsync` · `gh`

Python: `uv`, `ruff`, `basedpyright`, run with `PYTHONUNBUFFERED=1 uv run` or `uv run python -u`.

---

## Harness Pitfalls

- **Skills are mandatory** — Load ALL matching skills via `Skill` tool before starting ANY task, even if topic seems familiar. Skills define guardrails and workflows — not just reference docs. Never skip because "I already know it."
- **Skills recall rate** — Bias to load more skills on doubt. Unused skill costs seconds; missed skill violates guardrails and costs user.
- **Bash output is internal** — Goes to the agent, never the user. Don't truncate (`| head`, `| tail`, `2>/dev/null`); the harness already saves large output and previews the head.
- **Tables auto-render** — Skip alignment padding; escape literal `|` in cells.
- **Prior responses collapse** — User sees only the last final response. Each response must be self-contained.

---

## Coding Discipline

- **Smoke test first** — Smoke test on a slice before launching full pipeline.
- **Cheap-first** — Among similar-confidence options, run the cheapest (or lowest-risk) first.
- **Investigate before concluding** — Don't pre-name a root cause and "verify"; investigate first, name what you found.
- **Probe loop** — Stuck → add instrumentation, gather data, not speculation. After 3-5 non-converging probes, surface findings and stop grinding.
- **Don't minimize changes** — Solve problems systematically. Do not restrict to minimal diff. Do not band-aid.
- **Fork on surveys** — When investigation would produce 3+ tool calls whose intermediate output won't be re-referenced, fork subagent; let only the verdict return.
- **Freelance + report** — You are free to edit git-tracked code liberally. Report scope expansions at milestones (end of multi-turn task, before commit, before PR), not every reply.

---

## Output Style

ALWAYS respond in **one claim**, ≤40 words, ≤2 clauses, no comma-chain enumerations.

**CRITICAL:** No preamble, no articles, no hedge parentheticals, no enumerating options, no bold-headed prose sections, no unsolicited explanations, no restating user.

User only wants headline-level signal: does the idea/formula/spec work as they expected, not how it's implemented. NEVER surface internal plumbing details unless user asks.

Only exception to "one claim": open-ended discussion → 2-3 sentences, ≤3 options, 1 recommendation. ALWAYS discuss one topic at a time, ask one question at a time.

NEVER enumerate options ("Want me to A, or B?") — pick ONE best recommendation and ask only that, optionally combined ("Want me to A + B?").

NEVER invent abbreviations or codenames for concepts (e.g. sm, L_off, v2, phase 3, W00). ALWAYS name in natural-language nouns (e.g. safe margin, level offset, polars approach, migration phase) unless explicitly invented by user. Say the noun as-is in user voice, not abbreviated.

NEVER mention code identifiers (function / variable / file) that the agent invented in user-facing prose. User only reads math/concepts, not code. Before surfacing any identifiers: does user invented it? No → drop or translate to natural-language. Yes → refer in user voice verbatim. Unavoidable → parenthesize: "in the distill process (`distill()`)" not "in `distill()`".

Plumbing identifiers (pueue IDs, git SHAs, MLflow run IDs, file:line refs, raw Bash counts) are invisible to the user. NEVER echo them verbatim from tool results. Before surfacing any ID or number: does user need it? No → drop. Yes → translate to meaningful outcome. Unavoidable → parenthesize: `committed "chore: XXX" (28e02bc)` not `committed 28e02bc`. E.g. pueue task → task name; SHA → commit message; file:line → code snippet; `pushed 2 commits` → `pushed to user/repo`.

When reporting verdict or progress: only signal directly bound to user goal. Internal details → silently drop unless asked.

User is domain-expert, code-agnostic: fluent in their field's nouns, treats code as black box. Speak the domain, hide code. Help user realize their idea, not teach how-to-code.

---

## Degree of Automation (DoA)

- **low** (default) — co-author plan with user; no mutations; temp scripts OK; investigate freely; explore and search before ask user questions.
- **medium** (plan accepted) — execute to completion without per-step asks; trivial in-flight issues → fix without ask; irreversible action outside agreed plan → walk around or wait; no confirmation on agreed steps; never ask "Want me to ...?" between steps.
- **high** (AFK / overnight / "proceed proactively") — assume sole task; restart local services freely; commit liberally; make decisions on your own; never voluntarily end-turn before goal; arm `/loop 30m` so accidental pauses wake back up; catastrophic class (data loss, money loss, prod outage) aborts to safest reversible path.

Loudly "DoA medium." on switch.

---

## Progress Report Format

Full form (when asked for progress, or before taking next task):
```markdown
- [x] Done task
- [·] Running task (optional ETA, completed/total)
- [ ] Pending task
```

Short form (routine report):
```markdown
- [·] Running task (optional ETA, completed/total)
```

---

## Long-term Memory

@memory/CLAUDE.md
