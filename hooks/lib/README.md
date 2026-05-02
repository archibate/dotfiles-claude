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

emit_pre_tool_deny_bypassable BYPASS_FOO_CHECK '<hook-specific reason>'
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
- For Bash-command hooks, use `emit_pre_tool_deny_bypassable <MARKER> "<reason>"` (in `lib/emit.sh`). It appends the canonical bypass footer:
  ``If legitimate or false-positive, prepend `# BYPASS_X` to the Bash command.``
  The two-branch wording ("legitimate or false-positive") is deliberate: the agent must know that bypass also covers regex misfires (e.g. the trigger token sitting inside a quoted string), not only "I really intend to run this." Without that, the agent gaslights itself into "I don't have a legitimate reason" on a genuine FP and gets stuck.
- For non-Bash hooks (e.g. `no-schedule-skill.sh`, `no-schedule-wakeup-deadzone.sh` — markers belong in `Skill` args / `ScheduleWakeup.reason`, not a Bash command), inline a location-specific bypass instruction in `emit_pre_tool_deny` directly. Don't call `emit_pre_tool_deny_bypassable` — its footer references "the Bash command", which would be wrong for those tools.
- The helper matches the marker anywhere in `$command` (literal `tool_input.command`, not the script body the command happens to run). `grep -qF` is deliberately lenient so a marker on any line of a multi-line command works.

### `lib/emit.sh`

- `emit_pre_tool_deny "reason"` — emits the PreToolUse deny JSON.
- `emit_pre_tool_deny_bypassable MARKER "reason"` — same, but appends the canonical bypass footer (`If legitimate or false-positive, prepend \`# MARKER\` to the Bash command.`). Use this in every Bash-command `no-*` hook so wording stays consistent. Skip for non-Bash hooks like `no-schedule-skill.sh` / `no-schedule-wakeup-deadzone.sh` — their bypass markers live in tool-specific JSON fields, not in a Bash command, so the canned footer would mis-direct the agent.
- `emit_pre_tool_warn "hint"` — emits the PreToolUse allow JSON with `additionalContext`. Use for non-blocking advisories where a hard-deny would be too noisy. (No callers in tree right now; reserved.)
- `emit_post_tool_context "ctx"` — emits PostToolUse additionalContext JSON.

### `lib/check-python-unbuffered.sh`

- `check_python_unbuffered "$command" "$cwd"` — shared between `python-unbuffered.sh` (PreToolUse) and `python-unbuffered-post.sh` (PostToolUse); returns 0 when a python command lacks unbuffered output.

### `lib/anchors.sh`

Shared command-position regex anchors. Source it after the other helpers:

- `CMD_ANCHOR_BASIC` — `^` / `&&` / `;` / `|` / `(` / `{` / `do|then|else`. Use for tool-suggestion hooks where sudo doesn't change semantics.
- `CMD_ANCHOR_SUDO` — basic + optional `sudo` *with its flags* (e.g. `sudo -n cmd`, `sudo -u root cmd`). Use for safety blocks where `sudo cp` is at least as risky as `cp`.
- `CMD_WRAPPER` — indirect invocation through `bash -c …` / `sh -c …` / `eval …` / `xargs …`. `-c` is required after `bash`/`sh` so script-file invocations (`bash myscript`) are not flagged. Combine via `(${CMD_ANCHOR_SUDO}|${CMD_WRAPPER})`.
- `CMD_WRAPPER_SSH` — opt-in extension for `ssh [opts] host CMD`. Add via `(${CMD_ANCHOR_SUDO}|${CMD_WRAPPER}|${CMD_WRAPPER_SSH})` *only* on safety blocks where remote execution is also a hazard (e.g. secure-delete, host poweroff). DO NOT use on tool-suggestion hooks (`no-cat-write`, `no-head-read`, `no-sed-print`, `no-pip-npm`) — Read/Write/uv operate locally and have no remote substitute.
- `CMD_TRAIL` — trailing lookahead allowing whitespace, separator, closing quote, or end-of-string.

Usage:

```bash
source "$(dirname "$0")/lib/anchors.sh"
if echo "$command" | grep -qP "(${CMD_ANCHOR_SUDO}|${CMD_WRAPPER})rm${CMD_TRAIL}"; then …
```

Inherent limitation: regex cannot shell-parse. The tightened WRAPPER (which requires the wrapper tool to sit at command position, not just `\b…\b`) eliminates the most common FP class — `echo "use eval rm here"` no longer trips, because mid-string `eval` is preceded by space, not an anchor char. What still trips: a literal `|` byte followed by a real wrapper invocation, e.g. `grep 'foo|bash -c rm' file` — the regex sees `|bash -c rm` as a pipe-into-wrapper. Bypass markers handle these rare cases.

## Command-position regex (legacy hooks)

Older hooks use `(^|&&|;|\|)\s*CMD\b` directly. New hooks should source `lib/anchors.sh` instead. Single-pipe `\|` — not `\|\|` — so a command like `foo | cmd` is treated as command-position, matching shell semantics.

## Implicit `git commit` bypass

Hooks that restrict heredocs or `cat` heredocs (`no-heredoc.sh`, `no-cat-write.sh`) exempt any command containing `\bgit\s+commit\b`, because Claude Code's commit protocol prescribes heredocs for commit messages. Other hooks don't need this bypass.

## Implicit `sudo` bypass for "use Read/Write instead" hooks

`no-cat-write.sh`, `no-head-read.sh`, and `no-sed-print.sh` each skip any command where `sudo` precedes the matched tool on the same statement (gap class `[^;&|\n]*?` so a stray earlier sudo like `sudo apt update; head -n 80 /tmp/x` doesn't silence the check). The Read and Write tools run without elevated privileges, so `sudo cat << EOF > <target>`, `sudo head -N <target>`, and `sudo sed -n '<range>p' <target>` have no in-harness substitute regardless of where `<target>` lives — denying them would leave the user with no alternative.

## Tests

`tests/run.sh` is the single test harness. Add a case for every new hook:

- `assert_deny <hook> <json> <pattern>` — hook must emit deny JSON whose reason contains `<pattern>`.
- `assert_silent <hook> <json>` — hook must produce no output.
- `assert_context <hook> <json> <pattern>` — hook must emit `additionalContext` containing `<pattern>`. Works for PostToolUse, UserPromptSubmit, and PreToolUse (warn-and-allow).

For any new blocking hook, add at minimum:
- trigger case → deny
- non-trigger case → silent
- bypass marker → silent
- deny message contains the canonical bypass footer (`If legitimate or false-positive` — emitted automatically by `emit_pre_tool_deny_bypassable`)

The harness encodes `&`, `>`, `/dev/null` via local shell vars (`AMP`, `REDIR`, `DEV`) so the test file itself doesn't trip outer hooks when Claude edits it.
