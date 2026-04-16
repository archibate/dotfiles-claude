---
name: prompt-writing
description: >
  Guidelines for writing effective prompts across Claude Code — skill descriptions, CLAUDE.md rules,
  hook prompts, and agent configurations. This skill should be used when creating or reviewing
  skills, CLAUDE.md rules, hooks, or agent definitions.
allowed-tools: []
---

# Prompt Writing Guidelines

Principles for writing clear, effective prompts across all Claude Code configuration surfaces.

## Universal Principles

These apply everywhere — skills, CLAUDE.md, hooks, agents.

### Positive guidance over negative
Say what to do, not what to avoid. "Do NOT use X" causes undertriggering and defensive behavior.
- "Use defuddle for full page content" not "Do NOT use WebFetch for articles"
- "Use short, direct prose" not "Do NOT write long explanations"

### Explain the why, not just the what
Claude has good theory of mind. Explaining reasoning is more effective than rigid rules.
- "Bold is for structural labels (names, terms) — italic for light emphasis" not "NEVER use bold for emphasis"
- If you find yourself writing ALWAYS or NEVER in all caps, reframe as reasoning

### No hardcoded domain content
Keep prompts general. Don't bake in specific use cases that don't apply broadly.
- "For Chinese-language results, set `gl:cn hl:zh-cn`" not "For A-share market research, set `gl:cn hl:zh-cn`"

### Match the reader's context
The reader sees different amounts depending on the surface:
- Skill description → seen *before* loading, determines whether to load at all
- CLAUDE.md → always in context, every conversation
- Hook prompt → injected at tool-call time, sees only tool input/output
- Agent definition → full context for the subagent, nothing carried from parent

---

## Skill Descriptions

The `description` field determines whether a skill gets loaded.

### Must include
- What the skill does (one sentence)
- "This skill should be used when..." trigger conditions
- Anthropic notes Claude tends to undertrigger — descriptions should be slightly pushy

### Must avoid
- Negative instructions in description — save ❌/⚠️ for the SKILL.md body
- Mentioning other tools as alternatives — each skill describes itself
- Overly long descriptions — 2-3 sentences max

### SKILL.md body
- One-line summary → usage examples → tool selection guide → tips
- Code examples over prose
- Mark broken tools with ❌ *inside* the body, not in description
- Known limitations go in Tips section

For deeper skill development with eval frameworks and description optimization, see Anthropic's `skill-creator`.

---

## CLAUDE.md Rules

Always in context — every token costs every conversation.

### Keep it lean
- Rules that don't pull their weight waste context on every session
- Prefer a short principle over a long checklist
- "Default to short, direct prose" covers more than 10 specific formatting rules

### Override system defaults explicitly
- Claude Code's system prompt has defaults (e.g. "lead with the answer"). Override with reasoning:
  "Do NOT lead with the answer. Reason step-by-step BEFORE stating conclusions — reasoning tokens improve quality."
- Name what you're overriding so future readers understand the intent

### Anti-slop as principles, not lists
- ~~**Important:**~~ ~~**Note:**~~ — "if it's important the reader will know from context"
- Explain the aesthetic you want rather than listing every banned pattern

---

## Hook Prompts

### Command hooks (exit 2) vs prompt hooks
- Command hooks (bash scripts): see tool input via stdin JSON, output to stderr, exit 2 to deliver message
- Prompt hooks (inline text): injected into context, Claude processes and responds
- Command hooks are cheaper (just a message), prompt hooks cost more (Claude thinks + responds)
- Prompt hooks can block the main thread — use sparingly

### What hooks can and cannot see
- Command hooks: see tool input JSON (file_path, old_string, new_string, etc.)
- Prompt hooks: see only the incremental change, not the full file
- Full-file checks (syntax, style consistency) → command hook exit 2 → Claude reads file itself
- Incremental checks (slop detection) → can work in prompt hooks but beware hallucinated judgments

### Keep hook messages actionable
- "Re-read X to check: stale content, contradictions, style consistency" — specific checklist
- Not "Something might be wrong, please check" — vague anxiety

---

## Agent Definitions

### Tool lists are the agent's world
- The agent only has tools you list — no access to parent's loaded skills
- Include Skill tool if the agent should load skills on demand
- Be explicit about what each tool does in the agent's context

### Accurate tool descriptions with tested behavior
- Document actual tested behavior, not marketing claims
- "WebSearch — best for English/international queries. No region targeting."
- "WebFetch — may truncate, summarize, or refuse long content."
- "jina search_web — finds local community content (知乎, AcFun, AWA) that WebSearch misses"

### Decision guidance
- When multiple tools serve similar purposes, explain when to pick which
- "Simple searches → self. Deep multi-source investigation → web-researcher agent."

---

## Reviewing Existing Prompts

Checklist:
1. Does it have a positive "when to use" trigger? If only negative, rewrite
2. Are there rigid MUST/NEVER rules? Reframe as reasoning
3. Hardcoded domain content? Generalize
4. Does the description match actual tested behavior?
5. Are known limitations in the right place (body/tips, not description)?
6. Is it lean — does every line earn its context cost?
