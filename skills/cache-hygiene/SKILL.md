---
name: cache-hygiene
description: >
  Prompt cache cost optimization. Generates periodic conversation turns to keep the
  5-minute prompt cache warm during idle gaps. Auto-triggered after launching background
  agents; also invocable manually (`/cache-hygiene`) when the user will be away. Not
  needed for Bash background tasks (use Monitor for those — its events keep the cache
  warm naturally).
---

# Cache Hygiene

Prompt cache cost optimization protocol. The prompt cache has a 5-minute TTL. A cache miss costs 1.25x vs 0.1x for a hit — keeping the cache warm saves ~1.15P per avoided miss.

## When to Use

- **Auto-triggered** (via hook): after launching a background agent (no stdout stream to monitor).
- **Manual** (user types `/cache-hygiene`): user signals they will be away. Start the keep-alive loop after ending the current response.

Not needed for Bash background tasks — use Monitor with ~270s timeout instead, its events keep the cache warm naturally.

## Keep-Alive Protocol

Start a keep-alive loop:

```
/loop Cache keep-alive.
```

Each tick:
1. Call `ScheduleWakeup` with `delaySeconds=270` to stay within the 5-min cache TTL. Pass the same prompt verbatim.
2. End your response.

Stop (omit `ScheduleWakeup`) when the idle period ends — agent completes, user responds, or the wait condition resolves. Also stop after 10 consecutive ticks with no user interaction and no background tasks — beyond that, cumulative keep-alive cost (10 × 0.1P) exceeds the one-time cache miss penalty (1.15P).

## Blocking Call Cap

Never block a single tool call for >4 minutes (Bash `timeout`, `TaskOutput`). The cache TTL ticks during blocking calls — a 4-minute block plus response overhead can bust the 5-minute window. The keep-alive protocol prevents misses *between* turns; this cap prevents misses *within* turns.
