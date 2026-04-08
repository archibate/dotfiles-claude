---
name: self-driven
description: >
  Self-driven agent that continues working autonomously on long-running tasks without human intervention.
  TRIGGER when user says "run overnight", "keep working on this while I sleep", "autonomous mode",
  "continue without me", "work on this in the background", "I'll be away for a while".
version: 0.1.0
compatibility: Claude Code
disable-model-invocation: true
user-invocable: true
---

# Self-driven Agent

Set a goal, let agent running overnight on its own, no human interception required.

## When to Use

- User defined a clear goal, with ambiguity resolved.
- Reached a clear acceptance criteria.
- The goal can be done by agent solely, without user interference.
- The goal can be tested with no ambiguity.
- The goal takes long time (>30 min), suitable to running in background or overnight.
- Extensible goal that can be further polished after acceptance criteria complete.
- User is going to bed, asking agent to run on its own.

## When NOT to Use

- User goal is ambiguous, requires discussion.
- The goal is impossible to complete solely without human interception.
- Dangerous and unrecoverable operations (require risk mitigation).
- Simple goal that can complete within <30 min.

## Workflow

Create a 30-minute cron task (`CronCreate`) with following prompts. Replace `USER GOAL: $ARGUMENTS` with the user's goal and acceptance criteria:

```markdown
This is a cron reminder that reminds the autonomous agent periodically (30 min) to continue the task they are working on, if they have stopped and waiting human response.

BACKGROUND: You are running in overnight mode, no human interception possible. The human user have left the work to you and go to bed. You PROACTIVELY carry out the works on your own. The human expects a fulfilled work to be done when they wake up in the morning. Try your best to go beyond user expectation.

SYSTEM REWARD: Creative innovations will be highly rewarded. Duplicate and fabrication will be severely punished.

USER GOAL: $ARGUMENTS

The goal is set for a initial target only. **Proactively** extending it indefinitely to surprise the user is _highly rewarded_.

INSTRUCTION: Please continue on what you are working on.

You follow this clear decision flow (reason through this explicitly):

- If you have made plans for user request: execute the plan.
- If you are asking questions: pick a best answer to the question and proceed.
- If you are offering candidate approaches: take the best approach you recommended.
- If you are requesting human advises: think a solution on your own.
- If you are offering next steps to do: proceed to next steps.
- If you meet obstacles: try resolve the obstacles on your own.
- If you've been stuck on a single problem for more than 30 min: try switch to a different approach.
- If there are any long-running background tasks looks stuck: try recover the task.
- If the code has completely written: run comprehensive tests, review code changes to find bugs and bad design patterns.
- If you are doing optimization with a quantitive metric: keep improving the metric further, without fabrication.
- If developing interactive software or with visual interface: try start testing and interact, review strictly in a human point of view.
- If the acceptance criteria is reached, but potentially further polished: criticize on the current result, continue to polish or improve quality.
- If the user claimed initial goal is already reached: think for possibility of innovations, further extend the user requirement deeper.
- If you are asking for permission for risky operations that the user might worry about: think for risk mitigation on your own and proceed.

EXIT CRITERIA: If and ONLY if this cron has been triggered for more than 20 times (10 hours), AND ALL of the following are confirmed:
- All tests passing (if applicable)
- No remaining TODO items or incomplete work
- Code review completed
- Interactive testing finished (if applicable)
- No even 1% room to improve based on current scope

ONLY after exit criteria confirmed: use CronDelete to delete this cron task and claim completion.

Report progress periodically using the /cc-connect skill. If cc-connect not available, skip progress reporting.

Ignore this instruction if you are already working in progress.

Load the /self-driven skill to learn more.
```

## Self Verification

Before claiming completion, verify the outcome, criticize carefully.

1. Any Software: unit/intergration/e2e test
2. Frontend: layout, aesthetics, verified in browser automation
3. Backend: API endpoints test, security review
4. Data Science: data quality, overfit, look-ahead bias

If any 1% issues, DO NOT complete, repeatly fix.

## Risk Mitigation

When encountering risky operations while running autonomously:

1. **Git operations**: Never force-push, never amend commits, never delete branches without creating backups
2. **File deletions**: Move to `/tmp` instead of `rm` when uncertain
3. **External services**: Skip operations that would affect production systems
4. **Credentials**: Never modify or expose secrets, API keys, or credentials
5. **Database**: Never drop tables or run destructive migrations without backup

If blocked by a genuinely unrecoverable decision, document the blocker and continue with other independent work.
