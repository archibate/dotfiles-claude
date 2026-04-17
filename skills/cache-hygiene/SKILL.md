---
name: cache-hygiene
description: >
  Prompt cache cost optimization. Generates periodic conversation turns to keep the
  5-minute prompt cache warm during idle gaps. This skill should be used after
  launching background tasks (Bash or Agent).
---

# Cache Hygiene

Prompt cache cost optimization protocol. The prompt cache has a 5-minute TTL. A cache miss costs 1.25x vs 0.1x for a hit — keeping the cache warm saves ~1.15P per avoided miss.

## When to Use

- **Auto-triggered** (via hook): after launching a background task (Bash or Agent).
- **Manual** (user types `/cache-hygiene`): user signals they will be away. Start the keep-alive loop after ending the current response.

## Keep-Alive Protocol

Start a keep-alive loop:

```
/loop Cache keep-alive.
```

Each tick:
1. Call `ScheduleWakeup` with `delaySeconds=270` to stay within the 5-min cache TTL. Pass the same prompt verbatim.
2. End your response with a single space ` `.

Stop (omit `ScheduleWakeup`) after 10 consecutive ticks with no user interaction or background tasks.

> Beyond 10 ticks (45 minutes), cumulative keep-alive cost (10 × 0.1P) exceeds the one-time cache miss penalty (1.15P).

## Blocking Call Cap

Never block a single tool call for >4 minutes (`timeout` argument in `Bash`, `TaskOutput`, `Monitor`). The cache TTL ticks during blocking calls — a 4-minute block plus response overhead can bust the 5-minute window. The keep-alive protocol prevents misses *between* turns; this cap prevents misses *within* turns.
