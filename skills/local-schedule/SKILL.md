---
name: local-schedule
description: In-session scheduling via CronCreate. For "at <time>", "in <duration>", "remind me", "tomorrow". Defer to /schedule for remote.
---

# local-schedule

Route time-anchored task requests to `CronCreate` instead of the remote `/schedule` skill.

## When to use this vs /schedule

| Task needs… | Tool |
|---|---|
| Files / processes / cwd / state from THIS session | `CronCreate` (this skill) |
| To survive Claude restart | `CronCreate` with `durable: true` |
| To run as a remote agent independent of this session | `/schedule` |
| "Every Nm run /slash-cmd" — bare slash-command on an interval | `/loop` (tighter match for that exact pattern) |
| Pure prompt with no local dependency, user didn't specify | `CronCreate` (default — cheaper, faster, no remote spin-up) |

If unsure, prefer `CronCreate`. Local scheduling can do everything `/schedule` can do for an idle session; the reverse is not true. The exception is `/loop` — it's purpose-built for repeatedly invoking a slash command, so when the user's phrasing is essentially `every <interval> /<command>`, defer.

## How to schedule

Call `CronCreate` directly. The tool's own description has the cron syntax and runtime details — read it before composing the call. The pieces that matter most:

- **5-field cron in local time.** No timezone math. `0 9 * * *` is 9am wherever the user is.
- **One-shots use `recurring: false`** with minute/hour/day-of-month/month all pinned. For "at 22:00 today": resolve today's date, build `MM HH DOM MON *`, set `recurring: false`. The job auto-deletes after firing.
- **Recurring uses `recurring: true`** (the default) and auto-expires after 7 days. Tell the user about the 7-day cap when they ask for an open-ended recurring job.
- **Off-minute discipline.** When the user's time is approximate ("around 9", "hourly", "in an hour"), pick a minute that is NOT `0` or `30`. Every model defaults to `:00` and the fleet collides. Use `57 8 * * *` or `3 9 * * *` for "around 9am", `7 * * * *` for "hourly". Only honor `:00`/`:30` when the user names that exact time.
- **`durable: true`** only when the user explicitly asks the task to survive a session restart. Default in-memory mode is correct for "tonight" / "tomorrow morning" / "every 5 min for a while".

## Resolving relative times

The user's prompt-submit hook injects the current wall clock as `Message time: YYYY-MM-DD HH:MM:SS Weekday`. Use that as the anchor — do not guess.

- "in 30 minutes" → add 30 min to message time, pin the resulting minute/hour/dom/month, `recurring: false`.
- "tonight at 10" → today's dom/month, `0 22 ...` (user named `:00` exactly, so `:00` is fine).
- "tomorrow morning" → tomorrow's dom/month, pick `57 8` or `3 9`, `recurring: false`.
- "every weekday at market open" → `28 9 * * 1-5` (off-minute; user can correct if they meant 9:30 sharp).

If the message-time hook is absent, ask the user for the current time rather than guessing — cron mistakes are silent until the fire moment.

## What to put in the `prompt` field

The prompt fires as a fresh user turn in this session at fire time. Write it as if the user just typed it: enough context that the model can act without re-reading scrollback. Example:

- User says: "at 22:00 run the regression test on the branch I just pushed"
- Prompt: `Run the regression test on branch <name> that we pushed at <time>. Logs go to <path>. Report pass/fail and any new failures vs main.`

Don't write `"do the thing we discussed"` — fire-time context is just this session's history; the model can read it but a self-contained prompt is more reliable.

## After scheduling

Tell the user, in one line: what was scheduled, the resolved fire time in their local clock, and the cron expression you used. They need to see the cron string to catch a misread time. Save the returned job ID if you might need to cancel it later (`CronDelete`).

## When to defer to /schedule instead

Hand off to `/schedule` only when the user explicitly indicates one of:

- The task must run after this Claude session ends and `durable: true` isn't enough (e.g., they want it on a true cron schedule for weeks/months).
- The task should run in a clean remote environment — fresh checkout, no local mutations, no in-flight session state.
- They literally say "schedule it remotely" or "use /schedule".

In those cases, mention you're switching to `/schedule` and why, so the user can correct you if the locality assumption was wrong.
