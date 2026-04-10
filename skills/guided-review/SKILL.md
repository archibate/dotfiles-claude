---
name: guided-review
description: Review code/docs and fix issues one-by-one with codename tracking and guided next-3 recommendations.
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
  Use when the user says "review and fix", "guided review", "review X and fix issues",
  or wants an interactive review-then-fix cycle on code, config, docs, or skills.
argument-hint: "[target file, directory, or description]"
arguments:
  - target
---

# Guided Review

Review code or docs, create a codename-indexed issue list, then fix issues one-by-one
with the user choosing what to tackle next from a short recommendation of ~3 items.

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

### 2. Review and Produce Issue List

Write a structured review. Group issues by file or component. Assign each issue a
**short codename** with a category prefix derived from the file/component name:

- `P1`, `P2` for issues in a file/component starting with P
- `A1`, `A2` for auth-related issues
- `X1` for cross-cutting concerns
- If two components share a first letter, use a 2-letter acronym to
  disambiguate (e.g., `Pi1` for pipeline, `Gh1` for github)

Format each issue with: codename, one-line title, and a brief description of the
problem and suggested fix direction.

**Rules:**
- Keep codenames short (1-2 letter prefix + number)
- Group by component, not by severity
- Include both the problem and a concrete fix direction for each issue

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
