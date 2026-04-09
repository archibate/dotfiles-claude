# Task Monitoring with cc-connect cron

Use `cc-connect cron` to set up periodic monitoring for long-running background tasks.
A cron job runs a prompt on a schedule, checks progress, and sends notifications.

**Prerequisite:** Must be inside a cc-connect session (`CC_PROJECT` set).
If not, use the built-in `CronCreate` tool instead.

## Setting Up a Monitor

```bash
cc-connect cron add --cron "*/30 * * * *" --prompt "<MONITORING_PROMPT>" --desc "<unique label>"
```

The `--desc` must be unique so the cron can identify and self-delete later.

## Monitoring Prompt Structure

Customize this template to the specific tasks being monitored:

```markdown
You are a task monitoring assistant.

## Step 1: System Resource Check
Run: uptime && free -h | head -3 && df -h / | tail -1
- Adjust thresholds to this machine (check total RAM with `free -h` first)
- High load or low resources → alert and pause new tasks

## Step 2: Check Task Progress
Run: pueue status | rg 'Running|Queued|Success|Failed' | tail -15
Identify which tasks are running, completed, or failed.

## Step 3: Take Action
- If tasks are running: report progress (check logs with `pueue log <id> | tail`)
- If a step completed and next step is ready: start next step via pueue
- If all steps complete: report final results and self-delete this cron
- If a task failed: report the error

## Step 4: Notify
Use cc-connect send --message '<summary>' for all notifications.

## Self-Cleanup
When all work is done:
  cc-connect cron list          # find this job by description
  cc-connect cron del <id>      # delete it
```

## Notification Conventions

| Context | Prefix | Example |
|---|---|---|
| Status update | 🔔 | `🔔 Interday 80% complete, feature done. ETA 20min.` |
| Resource alert | ⚠️ | `⚠️ RAM free < 2GB, pausing new tasks.` |
| Task failure | ❌ | `❌ Task 123 failed (exit 1). Check pueue log 123.` |
| Pipeline complete | ✅ | `✅ Pipeline complete. 372 features, ICIR 2.516.` |

## Example: Full Pipeline Monitor

```bash
cc-connect cron add --cron "*/30 * * * *" --desc "pipeline-monitor-20260409" --prompt "You are a pipeline monitor.

Step 1: Check resources (uptime, free -h, df -h /).
Step 2: Check pueue tasks (pueue status | rg Running|Queued|Success|Failed).
Step 3: If interday+feature both complete and fe not started → start fe via pueue.
        If fe complete and train not started → start train via pueue.
        If train complete → report results, then self-delete:
          cc-connect cron list, find the job matching 'pipeline-monitor-20260409', cc-connect cron del <id>.
Step 4: Send progress via cc-connect send -m '<summary>'."
```

## Managing Crons

```bash
cc-connect cron list            # list all cron jobs
cc-connect cron del <id>        # delete a specific cron job
```
