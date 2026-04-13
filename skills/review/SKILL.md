---
name: review
description: Review code for bugs or AI slop patterns, then fix issues interactively.
allowed-tools:
  - Read
  - Grep
  - Glob
  - Edit
  - Write
  - Bash
  - TaskCreate
  - TaskUpdate
  - TaskGet
  - TaskList
  - Agent
when_to_use: >
  Use when the user says "review", "review changes", "review diff", "check my changes",
  "any bugs?", "look for bugs", "review and fix", "review AI slop", "check for AI patterns",
  "clean up AI code", or after completing a major code modification. Proactively offer to
  run after large multi-file edits.
---

# Review

Infer intent, scope, and review mode from what the user said. No formal arguments.

- **Agent**: `code-review` for bugs (default), `ai-slop-review` for AI slop, both for "full review"
- **Scope**: specific files if mentioned, `git diff` if uncommitted changes exist, else project directory

## Steps

### 1. Launch Review

Determine scope and launch the appropriate agent(s). Tell the agent the target
(file paths or `"git diff"`). For "full review", launch both agents in parallel.

### 2. Create Issue List

Assign each finding a short codename (1-2 letter prefix + number) and create
a `TaskCreate` for each. Present the summary list to the user.

### 3. Pick-Discuss-Fix Cycle

After creating the todo list, and after each resolved issue, recommend **exactly 3
next issues**. Format: `**codename** [severity] — issue title` (a brief recall of
*what* the issue is, not the fix direction). If fewer than 3 remain, show all remaining.

Then wait for the user to pick. The user will respond with:

- **A codename** (e.g., "P1") → fix it
- **"discuss X"** → explain your plan, wait for approval before fixing
- **"skip X"** → not fixing; mark as skipped, move on
- **"investigate X"** → research the issue, then recommend fix or skip

**Per-issue flow:**
1. Mark task `in_progress`
2. If discussion requested, explain the approach and wait for confirmation
3. Execute the fix
4. Mark task `completed` if fixed, `deleted` if skipped
5. Recommend next 3

**Rules:**
- Never fix without reading the relevant code first
- After each fix, show the next 3 — do not dump the full remaining list
- If the user's feedback during discussion changes the fix approach, adapt
- If investigation reveals the issue is not real, recommend skipping it

### 4. Wrap Up

When all issues are resolved or skipped:

1. Show a final tally table: issue codename, resolution (fixed/skipped)
2. Offer to commit if there are changes
