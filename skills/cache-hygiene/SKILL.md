---
name: cache-hygiene
description: >
  Prompt cache cost optimization. Generates periodic conversation turns to keep the
  5-minute prompt cache warm during idle gaps. TRIGGER immediately after any Bash or
  Agent call with `run_in_background=true`, or when the user says "cache keep-alive".
allowed-tools:
  - ScheduleWakeup
compatibility: Claude Code
---

# Cache Hygiene

Prompt cache cost optimization protocol. The prompt cache has a 5-minute TTL. A cache miss costs 1.25x vs 0.1x for a hit — keeping the cache warm saves ~1.15P per avoided miss.

## When to Use

- **Auto-triggered** (via hook): after launching a background task (Bash or Agent).
- **Manual** (user types `/cache-hygiene`): user signals they will be away. Start the keep-alive loop after ending the current response.

## Keep-Alive Protocol

Start a keep-alive loop:

```
/loop Cache keep-alive. Idle tick 1/10.
```

Each tick:
1. Monitor background tasks. Resolve stucks.
2. Call `ScheduleWakeup` with `delaySeconds=270`. Pass the same prompt, incrementing `N/10` — or reset to `1/10` if there was user/background-task activity this turn.
3. End your response with a single space ` ` if nothing to report.

Stop (omit `ScheduleWakeup`) when `N` would exceed 10.

> Beyond 10 ticks (45 minutes), cumulative keep-alive cost (10 × 0.1P) exceeds the one-time cache miss penalty (1.15P).

## Key Pitfalls

Always set up schedule at <5 minutes delay, otherwise prompt cache (5-min TTL) would costly invalidate.

Never block a single tool call for >4 minutes (`timeout` argument in `Bash`, `TaskOutput`, `Monitor`). The cache TTL ticks during blocking calls — a 4-minute block plus response overhead can bust the 5-minute window. The keep-alive protocol prevents misses *between* turns; this cap prevents misses *within* turns.
