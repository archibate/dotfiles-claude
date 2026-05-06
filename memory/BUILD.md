# MEMORY SYSTEM

Recipes for building and maintaining the long-term memory system.

## INIT INSTRUCTION

Mine my Claude Code transcripts at ~/.claude/projects/**/*.jsonl into a curated long-term memory file ~/.claude/memory/promoted.md, intended for @-include in ~/.claude/CLAUDE.md.

Pipeline (parallelize via subagents where volume warrants):

1. DISTILL → ~/.claude/memory/distilled/<slug>.md per project (one .md per cwd). Read each session's JSONL, order events by timestamp, keep only user (string content) and assistant (text blocks) where isSidechain=false. Drop <system-reminder>, <command-*>, <task-notification>, "Cache keep-alive..." ticks, "<<autonomous-loop...>>" sentinels.

2. EXTRACT per .md → bullet nuggets. Each: STANDING-RULE claim + line citation + tag in {ai-default-conflict, repeated-correction, costly-correction, trial-and-error, system-mutations, env-facts} → ~/.claude/memory/distilled/extracted/<num>-<slug>.md

3. CLUSTER across projects → one merged file. H2 themes (8–14); merge near-duplicates; carry `(×N sources)` cross-project recurrence count → ~/.claude/memory/distilled/extracted/_merged.md

4. TRIAGE → prepend each bullet with `- [+]`, `- [-]`, or `- [?]` → ~/.claude/memory/distilled/extracted/_triaged.md

5. PROMOTE → ~/.claude/memory/promote.py merges `_triaged.md` into promoted/pending/rejected.md. For a fresh INIT (no carryover desired), `rm` the three destination files first. promoted.md: pure claim text under themed H2; pending keeps `[?]` markers; rejected keeps citations and metadata.

KEEP: AI-default conflicts, costly corrections, repeated corrections, hard env facts (working projects, tool versions, services, API endpoints, crontab, hardware, identity), system mutations, cross-project recurrence ≥2.

DROP: in-flight project state, AI defaults, narrow trial-and-error empirical findings, project-internal mechanics, claims too narrow to justify always-loaded cost.

Bias FALSE NEGATIVES > false positives — promoted memory pollutes every future Claude session. Target ~50–70 nuggets. Head to BUILD INDEX after promoted.md creation.

### VALUE MAP

是否值得加入持久记忆，价值评估：

加分项：
- AI 不知道就会犯错，纠正成本很高
- 用户花费大量时间试错产生的结果
- 用户反复纠正 AI 的点，浪费了用户不少时间
- 用户的要求与 AI 默认行为不符的部分

扣分项：
- 频繁变化的中间产物，写入持久记忆后需要频繁更新
- AI 默认就会做的事
- 偶然的问题，不太可能再次用到
- 网上找得到的知识

## UPDATE INSTRUCTION

Incremental update of ~/.claude/memory/. Same KEEP/DROP rules and FALSE-NEGATIVE bias as INIT.

  CONTEXT — do NOT re-extract claims already present in any of:
  - promoted.md, pending.md, rejected.md, cleaned.md
  - distill.py — anchors `--since` on distill-history.md
  - promote.py — merge-mode (carryover preserved, dedup by claim text)

  PIPELINE:

  1. DISTILL: `~/.claude/memory/distill.py`. Outputs `~/.claude/memory/distilled/<slug>.md`, one per project cwd. Pass `--since YYYY-MM-DD` to override the auto-anchor.

  2. EXTRACT in parallel (one general-purpose subagent per .md). Each agent reads its assigned .md and writes bullets to `/tmp/memory-extract/<slug>.md` in the same format as INIT step 2. Give each agent the H2 theme list of promoted.md.

  3. CLUSTER+TRIAGE in main thread:
     - Read all /tmp/memory-extract/*.md.
     - Build `distilled/extracted/_triaged.md` with NEW-round bullets only.
     - Mark each `- [+]`, `- [-]`, or `- [?]` under H2 themes matching existing promoted.md.
     - Borderline conflicts with existing memory → [?].
     - Bullet format promote.py parses:
         - [+/-/?] CLAIM TEXT [tag] (×N sources)
           cited: <slug>:L<line>      ← 2-space indent continuation, optional

  4. AUTO-RESOLVE [?] (default):
     - For each [?] in `_triaged.md` and `pending.md`, default to `[-]` UNLESS the bullet adds standalone value not already captured in BUILD.md or any memory file.
     - If a [?] flagged a contradiction with an existing `promoted.md` entry, edit promoted.md to delete or replace the stale entry FIRST, then resolve the [?].
     - Override: edit the marker before this step or say "stop at [?]".

  5. PROMOTE: `~/.claude/memory/promote.py`. Idempotent.

  6. REPORT & BUILD INDEX:
     - Counts: net-new [+] in promoted, audit [-] in rejected.
     - Then run pages.py.

## CLEAN INSTRUCTION

Audit ~/.claude/memory/promoted.md and prune entries matching any of:
  1. Completed historical events (e.g. a rename that has already happened, a one-time setup step).
  2. Legacy protocol/auth details for a path the same file already declares superseded by a current path.
  3. Vague meta-advice with no concrete future trigger.
  4. Version-pinned facts that will rot.
  5. Empirical results or numbers.
  6. Direct answer rediscoverable by a quick `rg`/`Read` in a known repo.

For each entry pruned:
  - If a durable kernel survives (methodology, conclusion, sweet-spot rule), keep that kernel and drop the specifics.
  - Otherwise delete the bullet entirely.

Write the originals (verbatim) into ~/.claude/memory/cleaned.md, grouped under their original section headers, each entry followed by a one-line deletion reason in parentheses. Then head to BUILD INDEX.

## AUDIT INSTRUCTION

Audit H2 classification in ~/.claude/memory/promoted.md. Section titles must be recall-friendly: title alone tells a future Claude which H2 to open.

Find and fix:
1. Catch-all sections (Misc, "quality", grab-bags) — redistribute their bullets, or split off a coherent subtheme of ≥3 bullets into its own H2.
2. Bullets filed under the wrong theme — move verbatim.
3. Section titles that don't reflect their actual content — rename.

Constraints:
- Move bullets verbatim. No edits to wording.
- Don't create new H2 with <3 bullets.
- Respect CLAUDE.md's "Avoid Taxonomy Hell" — only split when recall genuinely improves.

After editing promoted.md, head to BUILD INDEX.

## BUILD INDEX

Run `~/.claude/memory/pages.py`. Explodes promoted.md into one page per H2 topic under ~/.claude/memory/pages/{index.md,<slug>.md}. Prunes pages whose topics were removed.

First-time setup: add `@memory/pages/index.md` to ~/.claude/CLAUDE.md (path is relative to CLAUDE.md's directory).

## SCRIPTS TO USE

- distill.py for DISTILL
- promote.py for PROMOTE
- pages.py for BUILD INDEX
