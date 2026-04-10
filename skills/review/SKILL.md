---
name: review
description: Review code, docs, or uncommitted changes for bugs with verification-based methodology, then optionally fix issues one-by-one with codename tracking.
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
  "any bugs?", "look for bugs", "review and fix", "review X and fix issues", or after
  completing a major code modification. Proactively offer to run after large multi-file
  edits. This is the single entry point for all code review workflows.
argument-hint: "[target file, directory, or description]"
arguments:
  - target
---

# Review

Review code or docs via the review-engine agent, present a codename-indexed issue list,
then let the user choose which issues to fix interactively.

## Inputs

- `$target`: File, directory, or description to review. Defaults: if `git status` shows
  uncommitted changes, review those changed files. Otherwise review the current project
  directory.

## Goal

Produce a thorough review, then resolve every issue through a user-driven pick-discuss-fix
cycle. End state: all issues are either fixed, intentionally skipped, or deleted after
investigation. Offer to commit when done.

## Steps

### 1. Determine Scope

- If `$target` is provided, use it.
- If not, run `git status`. If there are uncommitted changes, scope to those files.
- If no changes, scope to the current working directory / project.

For small scopes (a few files), read them directly. For large scopes (a directory
with many files), use an Explore subagent to survey the codebase and return a
summary of key files and potential issues, then read specific files as needed.

### 2. Review via review-engine

Launch the `review-engine` agent with the resolved scope from Step 1:

- If scope is uncommitted changes: prompt the engine with target = `"git diff"`
- If scope is specific files/directory: prompt the engine with the file paths

The engine returns a findings table. Convert each row into a codename-tracked
issue. Assign **short codenames** with a category prefix derived from the
file/component name:

- `P1`, `P2` for issues in a file/component starting with P
- `A1`, `A2` for auth-related issues
- `X1` for cross-cutting concerns
- If two components share a first letter, use a 2-letter acronym to
  disambiguate (e.g., `Pi1` for pipeline, `Gh1` for github)

For each issue: codename, one-line title (from the engine's "Bug" column), and
a brief description combining the engine's "Root Cause" and "Suggested Fix".

**Rules:**
- Keep codenames short (1-2 letter prefix + number)
- Group by component, not by severity
- If the engine returns "No bugs found", tell the user and offer to end or
  broaden the scope

### 3. Create Todo List

Use `TaskCreate` for every issue. The task subject must include the codename:

> `P1: Extract shared daemon startup logic`

The description should contain enough context that either you or the user can
understand the issue without re-reading the review.

Present a summary list of all codenames and titles to the user.

### 4. Pick-Discuss-Fix Cycle

After creating the todo list, and after each resolved issue, recommend **exactly 3
next issues**. Format: `**codename** — issue title` (a brief recall of *what* the
issue is, not the fix direction). If fewer than 3 remain, show all remaining.

Then wait for the user to pick. The user will respond with:

- **A codename** (e.g., "P1") → fix it
- **"discuss X"** → explain your plan, wait for approval before fixing
- **"skip X"** → not worth fixing; mark as skipped, move on
- **"delete X"** → issue is not real; mark as deleted, move on
- **"investigate X"** → research the issue, then recommend fix or delete

**Per-issue flow:**
1. Mark task `in_progress`
2. If discussion requested, explain the approach and wait for confirmation
3. Execute the fix
4. Mark task `completed` if fixed. For skipped or deleted issues, set
   `metadata: {resolution: "skipped"}` or `{resolution: "deleted"}` before
   marking the task `deleted`
5. Recommend next 3

**Rules:**
- Never fix without reading the relevant code first
- After each fix, show the next 3 — do not dump the full remaining list
- If the user's feedback during discussion changes the fix approach, adapt
- If investigation reveals the issue is not real, recommend deleting it

### 5. Wrap Up

When all issues are resolved, deleted, or skipped:

1. Show a final tally table: issue codename, resolution (fixed/skipped/deleted)
2. Offer to commit if there are changes
