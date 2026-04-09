---
name: review-changes
description: Rigorously review uncommitted git changes for bugs, verifying claims against source code and mathematical correctness before concluding.
allowed-tools:
  - Bash(git diff:*)
  - Bash(git status:*)
  - Bash(git log:*)
  - Read
  - Grep
  - Glob
context: fork
when_to_use: >
  Use when the user says "review changes", "review diff", "check my changes",
  "any bugs?", "look for bugs", or after completing a major code modification
  (e.g. adding features, refactoring, fixing bugs). Proactively offer to run
  after large multi-file edits.
---

# Review Changes

Rigorously review all uncommitted git changes for bugs. Read the actual source
code — not just the diff — to verify every claim before concluding. Report
findings in a structured table with suggested fixes. Never apply fixes directly.

## Goal

Produce a bug report table for all uncommitted changes. Every entry must be
verified against source code. "No bugs found" is only valid after all
verification checks pass.

## Steps

### 1. Collect diff & context

Run in parallel:
- `git diff` (unstaged) and `git diff --cached` (staged)
- `git status` (check for untracked files that are part of the change)
- `git diff --stat` (summary of affected files)

Read any new untracked files in full.

**Artifacts**: List of changed files, hunks, and new files.

### 2. Read source files

For EACH changed file, read the surrounding code beyond the diff hunks:
- Function/class the change lives in (full body)
- Callers of changed functions (grep for usage)
- Definitions of variables/columns referenced in new code (grep to confirm they exist)
- Related constants, configs, or enums

**Rule**: Never review a diff hunk in isolation. Always read enough context to
understand the invariants the code must maintain.

**Artifacts**: Mental model of each change's dependencies and assumptions.

### 3. Verify each change

Apply these checks systematically to every hunk:

| Check | Method |
|---|---|
| Arithmetic / formulas | Algebraic substitution + one concrete numeric example |
| Off-by-one / counts | Count actual items in source, compare against declared counts |
| Variable dependencies | Grep for every referenced intermediate variable to confirm it exists upstream |
| Call-site consistency | When a signature changes, verify ALL callers pass args in correct order (positional and keyword) |
| Guard conditions | When a condition is changed, enumerate all flag/state combinations and trace each path |
| Doc-code sync | When docs update alongside code, verify docs match actual code behavior |

**Rule**: Do NOT conclude "no bugs" until every check has been performed.
Think through each check explicitly before writing any conclusion.

### 4. Report

Output a findings table:

```
| # | Severity | File:Line | Bug | Root Cause | Suggested Fix |
|---|----------|-----------|-----|------------|---------------|
```

Severity levels:
- **bug**: Incorrect behavior (wrong output, crash, off-by-one)
- **semantic**: Code works but meaning is wrong (inverted sign, misleading name)
- **nit**: Style, doc ordering, naming inconsistency

If no bugs found after all checks, state: "No bugs found. Verified: [list checks performed]."

End with a one-line summary: `N bug(s), M semantic issue(s), K nit(s) across L files.`
