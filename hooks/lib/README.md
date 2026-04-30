# Hook conventions

Shared helpers and house style for the PreToolUse / PostToolUse hooks in this directory's parent. New hooks should follow the same prologue so behavior stays consistent and bypass markers stay uniform.

## Standard prologue

```bash
#!/usr/bin/bash
set -euo pipefail

source "$(dirname "$0")/lib/bypass.sh"
source "$(dirname "$0")/lib/emit.sh"
source "$(dirname "$0")/lib/read_input.sh"

read_bash_command          # or: read_file_path
bypass_check BYPASS_FOO_CHECK

# detection — grep / regex against $command or $file_path

emit_pre_tool_deny '...
If you believe this is a false positive, add comment `BYPASS_FOO_CHECK` to the first line of command.'
```

Use `#!/usr/bin/bash` (not `/bin/bash` or `/usr/bin/env bash`). Always `set -euo pipefail`.

## Helpers

### `lib/read_input.sh`

- `read_bash_command` — sets `$input` (raw JSON) and `$command` (`.tool_input.command`); exits 0 if the command is empty.
- `read_file_path` — sets `$input` and `$file_path` (`.tool_input.file_path`, fallback `.tool_input.file`); exits 0 if neither is set.

### `lib/bypass.sh`

- `bypass_check MARKER` — if `MARKER` appears anywhere in `$command`, exits the hook with 0. Call it after `read_bash_command` and before detection so bypassed commands skip the expensive work.
- `has_bypass_marker MARKER` — non-exiting predicate (returns 0/1). Use for hooks with multiple independent checks that each carry their own marker — e.g. `no-git-amend.sh`, where `BYPASS_AMEND_CHECK` must not silence a chained `git push --force` or `git push --delete`. Pattern: `if <pattern-match> && ! has_bypass_marker BYPASS_X; then deny; fi`.

Conventions:
- Every `no-*` hook that blocks something must accept a bypass marker, so the user has an escape hatch.
- Marker names are `BYPASS_<SUBJECT>_CHECK` (e.g. `BYPASS_HEAD_READ_CHECK`) or `BYPASS_<SUBJECT>` (e.g. `BYPASS_CAT_WRITE`, `BYPASS_HEREDOC_RESTRICTION`).
- The deny message always ends with the exact line:
  ``If you believe this is a false positive, add comment `BYPASS_X` to the first line of command.``
- The helper matches anywhere in `$command`. The "first line" phrasing is a user-facing convention — `grep -qF` is deliberately lenient so a marker on any line works.

### `lib/emit.sh`

- `emit_pre_tool_deny "reason"` — emits the PreToolUse deny JSON.
- `emit_post_tool_context "ctx"` — emits PostToolUse additionalContext JSON.

### `lib/check-python-unbuffered.sh`

- `check_python_unbuffered "$command" "$cwd"` — shared between `python-unbuffered.sh` (PreToolUse) and `python-unbuffered-post.sh` (PostToolUse); returns 0 when a python command lacks unbuffered output.

## Command-position regex

Use `(^|&&|;|\|)\s*CMD\b` to match `CMD` at command position without matching it as a substring (`pipenv` shouldn't trigger `pip` rules). Single-pipe `\|` — not `\|\|` — so a command like `foo | cmd` is treated as command-position, matching shell semantics.

## Implicit `git commit` bypass

Hooks that restrict heredocs or `cat` heredocs (`no-heredoc.sh`, `no-cat-write.sh`) exempt any command containing `\bgit\s+commit\b`, because Claude Code's commit protocol prescribes heredocs for commit messages. Other hooks don't need this bypass.

## Tests

`tests/run.sh` is the single test harness. Add a case for every new hook:

- `assert_deny <hook> <json> <pattern>` — hook must emit deny JSON whose reason contains `<pattern>`.
- `assert_silent <hook> <json>` — hook must produce no output.
- `assert_context <hook> <json> <pattern>` — PostToolUse: hook must emit additionalContext containing `<pattern>`.

For any new blocking hook, add at minimum:
- trigger case → deny
- non-trigger case → silent
- bypass marker → silent
- deny message contains the standard "If you believe this is a false positive" hint

The harness encodes `&`, `>`, `/dev/null` via local shell vars (`AMP`, `REDIR`, `DEV`) so the test file itself doesn't trip outer hooks when Claude edits it.
