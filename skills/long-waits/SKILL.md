---
name: long-waits
description: TRIGGER when wait longer than 10 minutes, schedule tasks for delayed execution, set up a routine check, wait for background task to complete, or do something after a condition becomes true. TRIGGER when user says "run this X minutes later", "run this every X minutes", "periodically report progress", "watch the log every X minutes", "do X after Y complete", "wait for X then Y".
compatibility: Claude Code
---

# Long Waits

## Overview

Chain sequential background sleeps to wait for extended periods. Bash has a 10-minute (600,000ms) maximum timeout, so longer waits require multiple intervals triggered by completion notifications.

**Core insight:** Background tasks create an event-driven loop: start timer → receive completion notification → start next timer.

## When to Use

- "Wait until the checkin that fixes the widgets hits main, then rebase onto it, merge, and deploy"
- "Implement the spec after my tokens reset at 1am"
- "Run the live tests when the new version arrives on staging"
- "Periodically report progress of the pueue task by checking log"
- Any delay >10 minutes or condition that takes indefinite time

## Implementation

### Calculate Intervals

```
Total wait ÷ 10 minutes = Number of intervals
4 hours = 240 min ÷ 10 = 24 intervals
```

### Start First Interval

```bash
sleep 600  # With run_in_background: true
```

Returns immediately with task ID. Sleep runs asynchronously.

### Handle Notifications

When sleep completes, you receive `<task-notification>`. Start next interval:

```bash
sleep 600  # Next interval, run_in_background: true
```

Track with TodoWrite: `"Waiting interval 2/24 (10 min each, ~4 hours total)"`

### Execute

After final notification, perform the scheduled task.

## Wall Clock / Calendar Times

When the user specifies a target time (e.g., "at 3pm", "tomorrow at noon"):

1. **Check system time:** `date`
2. **Assume user's time zone** matches system. Don't ask.
3. **Calculate with Python:**
```bash
python3 -c "
from datetime import datetime
target = datetime(2024, 1, 15, 15, 0, 0)  # Jan 15, 3:00 PM
now = datetime.now()
diff = target - now
print(f'Seconds: {int(diff.total_seconds())}')
print(f'Minutes: {diff.total_seconds() / 60:.1f}')
"
```
4. **Verify** the output makes sense (positive, reasonable magnitude).
5. **Tell the user:** "I'm going to wait 3 hours, 25 minutes until 3:00 PM PT, then [task]."
6. **Convert to intervals** and execute.

## Condition-Based Waiting ("Do This After...")

For conditions like "after the deploy succeeds" or "after the file appears":

**Pattern:**
```
check condition → false? → sleep 600 (background) → notification → check again → true? → execute
```

1. **Translate to concrete check:**

| User says | Check |
|-----------|-------|
| "commit that fixes tests" | `git log` for message or CI status |
| "file contains 'ready'" | `grep -q "ready" ~/file.txt` |

2. **Establish baseline** for relative conditions ("two new versions").
3. **Tell the user:** "I'll check every 10 minutes for [condition]."
4. **Poll loop:** Check → if false, `sleep 600` (background) → on notification, repeat.
5. **Execute** when condition is true.

Track: `"Polling for [condition] - check #5 (started 50 min ago)"`

## Quick Reference

| Wait Time | Intervals |
|-----------|-----------|
| 30 min | 3 × sleep 600 |
| 1 hour | 6 × sleep 600 |
| 2 hours | 12 × sleep 600 |
| 4 hours | 24 × sleep 600 |

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Foreground sleep >10min | Bash timeout is 600,000ms max. Use background. |
| Missing `run_in_background: true` | Sleep blocks conversation. Always use background. |
| Not tracking progress | User has no visibility. Use TodoWrite. |
| Forgetting to verify time calculation | Check Python output before starting intervals. |
