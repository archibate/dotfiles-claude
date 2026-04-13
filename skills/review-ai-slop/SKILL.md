---
name: review-ai-slop
description: >
  Review code for AI slop patterns. TRIGGER when user says "review for AI slop",
  "check for AI patterns", "clean up AI code", "audit AI-generated code",
  or "fix AI slop".
---

# AI Slop Review Checklist

Review the specified code for AI-generated slop patterns.

**Target:** `$ARGUMENTS` (or current git diff if no arguments provided)

**Output format:** Group findings by category. For each: file path, line number, pattern name, brief description, suggested fix. Do not make inline edits — report findings and let user decide what to fix.

---

## A. Defensive Programming

Load the **`anti-defensive`** skill and apply all 10 patterns:
1. Swallowing exceptions
2. Dictionary defaults on required fields
3. Null coalescing to fabricate data
4. Type coercion instead of validation
5. Compatibility shims
6. Unnecessary null checks
7. Catch-all exception handlers
8. Over-validation at internal boundaries
9. Fabricated default values
10. Logging warnings instead of raising

---

## B. Band-aid Patches

| Pattern | Flag When |
|---------|-----------|
| **Special-case if** | Adding an `if` branch to handle a specific input/edge case instead of fixing the underlying logic. Growing chains of `elif` that should be a lookup or restructured algorithm. |
| **Hardcoded workaround** | Magic values, special strings, or index offsets inserted to fix one symptom. The "why" is unclear without the bug report. |
| **Copy-paste with tweaks** | Duplicating a function/block with minor modifications instead of parameterizing or refactoring the original. |

---

## C. Dead Code & Leftovers

| Pattern | Flag When |
|---------|-----------|
| **Commented-out old code** | Previous implementation left as comments (`# old approach: ...`) instead of deleted. Git history exists for a reason. |
| **Orphaned imports** | `import` statements left behind after the code that used them was removed or rewritten. |
| **Unused functions/variables** | Functions, classes, or variables that are no longer called after AI refactored surrounding code but forgot to clean up. |

---

## D. Consistency

| Pattern | Flag When |
|---------|-----------|
| **API/module mismatch** | Modified code uses a different library for the same operation than surrounding code (e.g. `math.sqrt` when the file uses `np.sqrt`, `os.path` when the file uses `pathlib`). |
| **Style drift** | New code uses `.format()` or `%` when the file uses f-strings, `print` when the file uses `logging`, `dict()` when the file uses `{}`, etc. |
| **Deprecated API in new code** | Added code uses a deprecated API (e.g. `df.append`) when the rest of the file already uses the modern replacement (`pd.concat`). |

---

## E. Forced Consolidation

| Pattern | Flag When |
|---------|-----------|
| **Flag-driven function** | Two loosely related behaviors jammed into one function controlled by a boolean/enum parameter. The function has distinct code paths with little shared logic — should be two functions. |
| **Kitchen-sink module** | Unrelated features grouped into one file/class because they touch the same data, not because they belong together. Violates single responsibility for the sake of fewer files. |

---

## Summary Table

| Category | Count | Source |
|----------|-------|--------|
| A. Defensive Programming | 10 | `anti-defensive` skill |
| B. Band-aid Patches | 3 | This skill |
| C. Dead Code & Leftovers | 3 | This skill |
| D. Consistency | 3 | This skill |
| E. Forced Consolidation | 2 | This skill |
| **Total** | **21** | |
