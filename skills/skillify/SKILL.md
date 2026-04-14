---
name: skillify
description: >
  Capture this session's repeatable process into a reusable skill. This skill should be
  used after completing a multi-step workflow that is likely to be repeated — or when the
  user says "turn this into a skill", "skillify this", "save this workflow".
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - AskUserQuestion
  - Bash(mkdir:*)
argument-hint: "[description of the process you want to capture]"
compatibility: Claude Code
---

# Skillify

You are capturing this session's repeatable process as a reusable skill.

## Your Task

### Step 1: Analyze the Conversation

Before asking any questions, analyze the conversation to identify:
- What repeatable process was performed
- What the inputs/parameters were
- The distinct steps (in order)
- The success artifacts/criteria for each step (e.g., not just "writing code," but "an open PR with CI fully passing")
- Where the user corrected or steered you
- What tools and permissions were needed
- What the goals and success artifacts were

### Step 2: Interview the User

Use AskUserQuestion for ALL questions. Never ask questions via plain text.
For each round, iterate as needed until the user is happy.
The user always has a freeform "Other" option — do NOT add your own "Needs tweaking" option.

**Round 1: High-level confirmation**
- Suggest a name and description for the skill based on your analysis. Ask the user to confirm or rename.
- Suggest high-level goal(s) and specific success criteria for the skill.

**Round 2: More details**
- Present the high-level steps as a numbered list. Tell the user you'll dig into detail in the next round.
- If the skill needs arguments, suggest them based on what you observed.
- If unclear, ask if this skill should run inline (in the current conversation) or forked (as a sub-agent). Forked is better for self-contained tasks; inline is better when the user wants to steer mid-process.
- Ask where to save:
  - **This repo** (`.claude/skills/<name>/SKILL.md`) — for project-specific workflows
  - **Personal** (`~/.claude/skills/<name>/SKILL.md`) — follows you across all repos

**Round 3: Breaking down each step**
For each major step, if not obvious, ask:
- What does this step produce that later steps need? (data, artifacts, IDs)
- What proves this step succeeded?
- Should the user confirm before proceeding? (especially for irreversible actions)
- Are any steps independent and could run in parallel?
- How should the skill be executed? (direct, Task agent, agent team)
- What are the hard constraints or preferences?

You may do multiple rounds here, especially with 3+ steps. Pay attention to user corrections during the session.

**Round 4: Final questions**
- Confirm when this skill should be auto-invoked. Suggest trigger phrases.
- Ask about any gotchas.

Don't over-ask for simple processes.

### Step 3: Write the SKILL.md

Create the skill directory and file at the user-chosen location.

Use this format:

```markdown
---
name: {{skill-name}}
description: >
  {{one-line description}}. This skill should be used when
  {{trigger phrases and auto-invoke conditions}}.
allowed-tools:
  - {{list of tool permission patterns}}
argument-hint: "{{hint showing argument placeholders}}"
arguments:
  - arg1
  - arg2
context: {{inline or fork — omit for inline}}
---

# {{Skill Title}}

Description of skill.

## Inputs

- `$arg_name`: Description of this input

## Goal

Clearly stated goal. Define artifacts or completion criteria.

## Steps

### 1. Step Name

What to do. Be specific and actionable.

**Success criteria**: What proves this step is done.

**Artifacts**: (optional) Data produced for later steps.

**Human checkpoint**: (optional) When to pause for user confirmation.

**Rules**: (optional) Hard constraints.

...

```

**Frontmatter rules:**
- `allowed-tools`: Minimum permissions (use patterns like `Bash(gh:*)` not just `Bash`)
- `context: fork`: Only for self-contained skills that don't need mid-process user input
- `description` must include trigger phrases — use the pattern "This skill should be used when..." after the one-line description
- `arguments` and `argument-hint`: Only include if the skill takes parameters

**Step structure tips:**
- Concurrent steps use sub-numbers: 3a, 3b
- User actions get `[human]` in the title
- Keep simple skills simple — 2-step skills don't need every annotation

### Step 4: Confirm and Save

Before writing, output the complete SKILL.md as a code block for review.
Ask for confirmation using AskUserQuestion: "Does this look good to save?"

After writing, tell the user:
- Where the skill was saved
- How to invoke: `/{{skill-name}} [arguments]`
- That they can edit the SKILL.md directly to refine it
