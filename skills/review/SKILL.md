---
name: review
description: >
  Review code for bugs or AI slop patterns, then fix issues interactively.
  This skill should be used after completing a major code modification or large multi-file
  edits — or when the user says "review", "review changes", "any bugs?", "review AI slop",
  "clean up AI code".
allowed-tools:
  - Read
  - Grep
  - Glob
  - Edit
  - Write
  - Bash(git diff:*)
  - Bash(git status:*)
  - Bash(git log:*)
  - Bash(git show:*)
  - TaskCreate
  - TaskUpdate
  - TaskGet
  - TaskList
  - Agent
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

### 2b. Quick Wins

Mark issues that are mechanical, behavior-preserving, and need no design decisions
with `*` on the severity column (e.g., `high*`). Add a footnote:
`*quick-win: can be batch-fixed without behavior changes`. Then offer to fix all
quick-wins before entering the interactive cycle.

### 3. Pick-Discuss-Fix Cycle

After creating the todo list, and after each resolved issue, recommend **exactly 3
next issues**. Format: `**codename** [severity] — issue title` (a brief recall of
*what* the issue is, not the fix direction). If fewer than 3 remain, show all remaining.

Then wait for the user to pick. The user will respond with:

- **A codename** (e.g., "P1") → fix it
- **"discuss X"** or **"explain X"** → explain the bug, the fix plan, and downstream impact (what would need re-running/rebuilding if fixed). Wait for approval before fixing.
- **"skip X"** → not fixing; mark as skipped, move on
- **"investigate X"** → research the issue, then recommend fix or skip

**Per-issue flow:**
1. Mark task `in_progress`
2. If discussion requested, explain the approach and wait for confirmation
3. Execute the fix
4. **Smoke test**: verify the fix with a quick import check or minimal script that exercises the changed path. If the test reveals the fix is wrong, revise before marking complete.
5. Mark task `completed` if fixed, `deleted` if skipped
6. If the fix changes behavior/schema, offer to run the relevant downstream action (test, build, smoke test on real data, etc.). If display-only or pure refactor, just note it and move on.
7. Recommend next 3

**Rules:**
- Never fix without reading the relevant code first
- After each fix, show the next 3 — do not dump the full remaining list
- If the user's feedback during discussion changes the fix approach, adapt
- If investigation reveals the issue is not real, recommend skipping it

### 4. Wrap Up

When all issues are resolved or skipped:

1. Show a final tally table: issue codename, resolution (fixed/skipped)
2. Summarize downstream actions required (re-runs, rebuilds, tests, migrations, etc.)
3. Offer to commit if there are changes
