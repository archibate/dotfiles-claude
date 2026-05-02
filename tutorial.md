# C-s: stash prompt

# !: inplace bash command

# C-g: edit prompt in nvim

# /vim mode? I don't use that

# C-r to search history prompt

# full screen mode

`/tui fullscreen` or `CLAUDE_CODE_NO_FLICKER=1`

`PageUp`, `PageDown` or mouse wheel to virtual scroll, superior to terminal built-in.

mouse drag to copy text selection, OSC 52 clipboard protocol (Kitty).

`/` to search, `n` and `N` to navigate.

plus `"autoScrollEnabled": false` in settings.

`/focus` mode, reduce cognition overhead.

# C-o: view detailed transcript

in this mode:
- `v` to edit detail transcript in Nvim.
- `[` to flush transcript to terminal.

# /copy or /copy 1 to copy response

# /btw [question]

/btw for quick side question without adding to main context
can fork by `f` when interested to continue

# /clear for new tasks, context tokens are not just money, but also attention

keep fresh mind, no maintaining a single long conversation

long context is not only expensive, but also reduce 'IQ': too noisy, cannot focus attention to the actual task

# /compact frequently, no wait for auto-compact

if you worry about losing things permanently, /compact. this makes the mind clean with prior knowledge and key findings preserved.

# ask to start subagent for things you only need conclusion, no steps, save context

# /rewind (esc esc) to correct

will rewind code changes, saves context (for both token cost and cognition overhead)

# /context to visualize

# /rename and /color to identify

useful when you have a lot parallel sessions.

# /resume to get back previous conversation

or `claude -r`, and `claude -c`.

# /recap if you forget

# prefer modern Kitty/Ghostty terminal

with clipboard support, notification support.

# tmux for multiplexing + persistency

set up clipboard and passthrough in tmux. if you don't know, you can copy my config.

# worktrees

`claude -w name`

or ask agent to switch in worktrees before implement.

ask "merge to main worktree" after implementation complete.

# prefer --bypass-permissions

claude is smart enough, will proactively pause and ask confirmation on dangerous irreversible operations.

```json
  "permissions": {
    "defaultMode": "bypassPermissions"
  },
```

saves tons of 'Yes', relieves your brain.

may also try, auto-mode for Max subscription users (I did use that).

# prefer hooks than CLAUDE.md rules

# use hooks to hint skills

# why skill is under-used?

they say "Execute skill" making agent fear of side-effects. should be "Load skill". but some skills do have execution, tho our main usage is use skills as pure reference and workflow definition. fuck Anthropic for 'security worth max' mindset.

# anti-system output style override

do not lead with conclusion - harms conclusion quality, LLM auto-regressive nature.

Fuck starting with "Root Cause:", "No. Here is why:", "Recommendation: Do A."

show reasoning first.

when offering options, list all candidates and reasoning, then recommend at last.

# `/loop` for periodic check

# background tasks

Bash and subagent can start in background.
Bash auto-background in 2 min by default (max to 10 min configurable by agent `timeout:`).
Agent default to no auto-background, can enable by `CLAUDE_AUTO_BACKGROUND_TASKS=1`.
C-b for manually make tasks background.
or ask agent to start in background, they will use `run_in_background: true`.

# prompt 5-min TTL mitigation

- what is prompt cache? cache invalidates in 5-min. cached tokens are cheaper, 0.1x cost. write tokens (for new arriving inputs and outputs) to cache costs 0.25x, so 1.25x for cache-miss on whole context, if you didn't respond in 5-min.
- keep-alive `/loop 5m`
- `CLAUDE_AUTO_BACKGROUND_TASKS=1` for auto-background agents
- `BASH_MAX_TIMEOUT_MS=240000` replace default 10 min timeout
- but Monitor replaces this strategy on background bash tasks

# new feature: Monitor tool

Monitor proactively triggers on background Bash output matching expression, and default to have 5-min timeout, exactly TTL boundaries (Anthropic purposely).

can ask claude to output a single space when nothing to report to prevent flood.

# Python background tasks needs `PYTHONUNBUFFERED=1` for real-time monitoring

otherwise may look stuck in claude, since claude use pipes to monitor background stdout

# configure status bar to display context and usage

install claude-hud or `/statusline`

# prefer Opus 4.7 + xhigh effort

# ultrathink keyword for one-use /effort max

# /ultraplan and /ultrareview (for subscribers, but I don't use it, no sense to me)

# 'manually' organize your project documentation (some people say memory)

auto-memory and auto-dream are trash to me, I don't use it

I'd maintain CLAUDE.md + references doc 'manually' (by asking claude to refactor, of course).

I've a `/doc-audit` skill to check docs are up-to-date to code, sync when out-of-date.

reduces claude cognition overhead, no risk of losing intent and clarification repeatedly in each new conversation.

# `/init` is trash

no better than not having one and let claude `Explore` to discover itself on each fresh conversation.

# hook to override `Explore` to sonnet (haiku hallucinate sucks)

# `/skills` or `/hooks` to list and toggle

# install plugin-dev plugin

/skill-development and /hook-development skill useful for developing

# `/skillify` from leaked source

# `/review` skill and its subagents: bugs and slops

# `/voice` for subscribers, but seems only English

# /config /status /stats /usage
