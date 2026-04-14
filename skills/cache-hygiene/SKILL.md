---
name: cache-hygiene
description: >
  Cache keep-alive protocol for background work. This skill should be used after launching
  a background agent or long-running background task (`run_in_background: true`). Keeps the
  5-minute prompt cache warm and prevents wasteful polling.
---

# Cache Hygiene

The prompt cache has a 5-minute TTL. A cache miss (re-write) costs 1.25x vs 0.1x for a hit — keeping the cache warm saves ~1.15P per avoided miss.

## Keep-Alive Protocol

After launching background work, immediately start a keep-alive loop:

```
/loop 5m Cache keep-alive. Peek background task progress briefly (non-blocking). Otherwise reply "ok".
```

Stop the loop (`CronDelete`) if it runs 10 consecutive iterations with no user interaction and no background tasks.

## Turn Discipline

- When a Bash command or agent is auto-backgrounded, briefly acknowledge it and **end your response**. Do not immediately read the output file or poll for completion.
- Never poll a background task in a loop without ending your response between iterations. Repeated blocking reads (TaskOutput, Read, tail) within a single turn hold the conversation hostage and bust the cache.
- On `/loop` keep-alive boundaries, it is OK to quickly peek progress (a single non-blocking read), then end your response. Do not spiral into repeated polling.

## Timeout Caps

- Prefer `run_in_background: true` for Bash commands or agents expected to exceed 2 minutes, so the turn unblocks immediately.
- Never pass `timeout` > 240000 (4 min) to TaskOutput. Use `block: false` for a quick non-blocking peek, or use the default 30s timeout. If the task isn't done, end your response and check again on the next loop boundary.
