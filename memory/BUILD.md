# MEMORY SYSTEM

Recipes for building and maintaining the long-term memory system.

## INIT INSTRUCTION

Mine my Claude Code transcripts at ~/.claude/projects/**/*.jsonl into a curated long-term memory file ~/.claude/memory/promoted.md, intended for @-include in ~/.claude/CLAUDE.md.

Pipeline (parallelize via subagents where volume warrants):

1. DISTILL → ~/.claude/memory/distilled/<slug>.md per project (one .md per cwd). Read each session's JSONL, order events by timestamp, keep only user (string content) and assistant (text blocks) where isSidechain=false. Drop <system-reminder>, <command-*>, <task-notification>, "Cache keep-alive..." ticks, "<<autonomous-loop...>>" sentinels.

2. EXTRACT per .md → bullet nuggets. Each: claim as STANDING RULE (not "today the user did X") + line citation + tag in {ai-default-conflict, repeated-correction, costly-correction, trial-and-error} → ~/.claude/memory/distilled/extracted/<num>-<slug>.md

3. CLUSTER across projects → one merged file. H2 themes (8–14); merge near-duplicates; carry `(×N sources)` cross-project recurrence count → ~/.claude/memory/distilled/extracted/_merged.md

4. TRIAGE → prepend each bullet with `- [+] ` (accept), `- [-] ` (reject), or `- [?] ` (manual review). Resolve all `[?]` in a follow-up pass; target 30–45% promote rate among pending. → ~/.claude/memory/distilled/extracted/_triaged.md

5. PROMOTE → split by marker into promoted/pending/rejected.md. promoted.md: pure claim text, themed H2 only. NO line citations, NO `[tag]`, NO `(×N sources)`. The audit files keep them.

KEEP: AI-default conflicts, costly corrections, repeated corrections, hard env facts (paths under ~, tool versions, API endpoints, hardware, identity), cross-project recurrence ≥2.

DROP: in-flight project state, AI defaults, narrow trial-and-error empirical findings, project-internal mechanics, claims too narrow to justify always-loaded cost.

Bias FALSE NEGATIVES > false positives — promoted memory pollutes every future Claude session. Target 50–70 nuggets, 2–3k words. Head to BUILD INDEX after promoted.md creation.

### VALUE MAP

是否值得加入持久记忆，价值评估：

加分项：
- AI 不知道就会犯错，纠正成本很高
- 用户花费大量时间试错产生的结果
- 用户反复纠正 AI 的点，浪费了用户不少时间
- 用户的要求与 AI 默认行为不符的部分

扣分项：
- 频繁变化的中间产物，写入持久记忆后需要频繁更新
- AI 默认就知道，默认就会做的事，不用记忆
- 偶然的问题，不太可能再次用到
- 网上找得到的知识，AI 下次很容易想到上网获取

## UPDATE INSTRUCTION

TASK: Incremental update of my long-term memory pipeline at ~/.claude/memory/.

  CONTEXT (read these first):
  - ~/.claude/memory/BUILD.md            — full build spec (DISTILL→EXTRACT→CLUSTER→TRIAGE→PROMOTE)
  - ~/.claude/memory/promoted.md         — current accepted memory (DON'T re-extract these)
  - ~/.claude/memory/rejected.md         — past [-] decisions (DON'T re-extract these either)
  - ~/.claude/memory/cleaned.md          — entries pruned post-promotion (DON'T re-extract these either)
  - ~/.claude/memory/distill.py          — supports --since YYYY-MM-DD for incremental
  - ~/.claude/memory/promote.py          — splits _triaged.md → promoted/pending/rejected.md (OVERWRITES)

  PIPELINE:

  1. DISTILL incrementally:
       ~/.claude/memory/distill.py --since $(stat -c %Y /home/bate/.claude/memory/promoted.md | xargs -I{} date -d @{} +%F)
     Outputs ~/.claude/memory/distilled/<slug>.md, one per project cwd.

2. EXTRACT in parallel (one general-purpose subagent per .md). Each agent:
   - Reads its assigned .md
   - Outputs bullets to /tmp/memory-extract/<slug>.md as:
       - [tag] STANDING-RULE CLAIM (cite: <slug>:L<line>)
   - Tags ∈ {ai-default-conflict, repeated-correction, costly-correction, trial-and-error}
   - Skip nuggets already in promoted.md / rejected.md / cleaned.md (give each agent the H2 theme list)
   - Bias FALSE NEGATIVES — promoted memory pollutes every future session
   - DROP: in-flight project state, AI defaults, googlable knowledge, narrow trial-and-error

3. CLUSTER+TRIAGE in main thread:
   - Read all /tmp/memory-extract/*.md
   - Mark each [+] / [-] / [?] under H2 themes matching existing promoted.md
   - Borderline conflicts with existing memory → [?]

4. RECONSTRUCT _triaged.md (CRITICAL — promote.py overwrites, no idempotence):
   - Backup: cp promoted.md promoted.md.bak; cp rejected.md rejected.md.bak; cp pending.md pending.md.bak
   - Build distilled/extracted/_triaged.md =
       (existing promoted.md bullets prefixed `- [+] ` and suffixed ` [carryover] (×1 sources)`)
       + (existing rejected.md bullets prefixed `- [-] `, keeping their [tag] (×N sources) + cited: continuation)
       + (new round, properly marked [+]/[-]/[?])
   - Same H2 may appear multiple times — promote.py merges them.
   - Bullet format that promote.py parses:
       - [+/-/?] CLAIM TEXT [tag] (×N sources)
         cited: <slug>:L<line>      ← 2-space indent continuation, optional

5. PROMOTE & VERIFY:
   - ~/.claude/memory/promote.py
   - diff promoted.md.bak promoted.md  →  must show ONLY `>` adds, ZERO `<` deletes
   - diff rejected.md.bak rejected.md  →  same check
   - If any deletion: restore from .bak and debug parser.

6. REPORT:
   - Counts: net-new [+] in promoted, audit [-] in rejected, [?] in pending.
   - Any [?] are blocking — list them; user must flip markers and re-run step 5.
   - Then head to BUILD INDEX.

## CLEAN INSTRUCTION

Audit ~/.claude/memory/promoted.md and prune entries matching any of:
  1. Completed historical events (e.g. a rename that has already happened, a one-time setup step).
  2. Version-pinned facts that will rot (specific Claude Code version numbers, specific model+hardware benchmark numbers).
  3. Legacy protocol/auth details for a path the same file already declares superseded by a current path.
  4. Vague meta-advice with no concrete future trigger.

For each entry pruned:
  - If a durable kernel survives (methodology, conclusion, sweet-spot rule), keep that kernel and drop the specifics.
  - Otherwise delete the bullet entirely.

Write the originals (verbatim) into ~/.claude/memory/cleaned.md, grouped under their original section headers, each entry followed by a one-line deletion reason in parentheses. Header: "# Cleaned from promoted.md" + today's date. Then head to BUILD INDEX.

## BUILD INDEX

Explodes promoted.md into ~/.claude/memory/pages/{index.md,<slug>.md}. One page per H2 topic, bullets verbatim, and prunes pages whose topics were removed. Run after any promoted.md update.

Lastly add @-include for index.md to ~/.claude/CLAUDE.md to activate memory.

## SCRIPTS TO USE

- distill.py for DISTILL
- promote.py for PROMOTE
- pages.py for BUILD INDEX
