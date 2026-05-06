---
name: doc-detrim
description: Audit agent-facing documentation (CLAUDE.md, SKILL.md, AGENTS.md, prompt markdown, agent reference doc, memory pages) for over-description and propose trims. Use proactively after writing or editing any agent-facing doc, or when the user says "trim this doc", "audit doc bloat", "this is over-explained".
argument-hint: "[doc files to trim]"
---

$ARGUMENTS
Audit this doc for over-description. The reader is a capable agent that can reason from naming and read referenced code. Flag and propose to trim: rationale repeated >1×; rules / tag-sets / lists restated across sections; justifying parentheticals after self-evident statements; defensive prose against dead or hypothetical workflows; behavior the code self-documents; symbol explanations the naming makes obvious. Bias toward trimming — keep only what changes behavior or removes real ambiguity.
