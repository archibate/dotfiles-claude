---
name: claude-dm
description: >
  Send peer-to-peer message and control to Claude Code sessions. Use when coordinating multiple simultaneous Claude sessions, or user says "dm another claude", "list claude sessions", "peek peer claude", "spawn claude in tmux", "monitor remote claude", "notify peer in tmux", "send to peer", "handover to claude", "inspect peer transcript", "orchestrate claude sessions".
---

# claude-dm

Peer-to-peer messaging between independent Claude Code sessions that share a tmux server.

## When to use

- Multiple Claude Code sessions are running on the same machine (check with `list`), and one needs to inspect or communicate with another.
- You need to know what another Claude is currently working on, without attaching to its tmux pane.
- You want to trigger a slash command (`/compact`, `/claude-dm`, etc.) in another session.
- Send a prompt to a peer and wait for the reply as data.

## When NOT to use

- To spawn a child Claude for one-shot work → use the `Agent` tool.
- To spawn a headless Claude from CLI → use the `/claude-headless` skill.
- To schedule a future Claude run → use the `CronCreate` (local) or `/schedule` (remote).
- To send a message to remote Claude on a different machine → see `portable/README.md`.

## Prerequisites

- Peers must run in tmux (any socket). Default resolution: `$CLAUDE_DM_SOCKET` or `/tmp/tmux-$(id -u)/default`.
- Peer must be spawned headful, not headless (`-p`).
- Same Unix user (or a shared socket with group perms).
- `claude-dm` available in `$PATH` (otherwise fallback to `bin/claude-dm` under skill dir).

## Verbs

```
claude-dm list                                 # roster of claude panes
claude-dm status <target>                      # state + safety gate result
claude-dm peek   <target> [N]                  # last N text blocks of peer's transcript
claude-dm tail   <target>                      # live-follow peer's JSONL
claude-dm wait   <target> [int_s] [to_s]       # block until peer reaches idle/modal
claude-dm send   <target> <msg>   [--force]
claude-dm cmd    <target> /<slash> [--force] [--confirm]
claude-dm ask    <target> <msg>   [timeout_s]
claude-dm esc    <target>          [--force]   # Escape: interrupt turn or cancel modal
claude-dm answer <target> <key>    [--force]   # pick modal option (1/2/3/y/n/a/…)
claude-dm self   /<slash>                      # queue a user-only slash command on the current pane
```

`<target>` is `session:window.pane` on the current socket (e.g. `HOME:8.1`).

`list` marks the current session's row with a trailing `*` on the ADDR column (e.g. `_claude:7.1*`). Strip the `*` before passing the addr to other verbs. Self detection only fires when `$CLAUDE_DM_SOCKET` matches the socket from `$TMUX`.

The `LAST` column shows compact elapsed time (`17s`, `8m`, `1h21m`, `3d20h`) since the peer's transcript JSONL was last written — useful for triaging which idle peers are stale-idle vs just-finished. `-` means no transcript could be resolved.

## Peer states

`peer_state` reports one of five values, shown in `status` and used by every gate:

| State | Meaning | Source signal |
|---|---|---|
| 🟢 `idle` | at `❯` prompt, buffer empty — safe to DM | title `✳` + empty box |
| 🔵 `busy` | streaming a turn / running a tool | title has spinner glyph |
| 🟠 `drafting` | human has unsubmitted text in the input | box contains non-menu text |
| 🔴 `modal` | permission / AskUserQuestion prompt open | box has ≥2 numbered options |
| ⚫ `other` | not a Claude REPL, or unknown UI | missing box/`❯` markers |

When state is `modal`, `status` also reports a subtype — `permission` (Bash/Edit/Write/Notebook being gated) or `question` (AskUserQuestion) — resolved from the most recent tool_use in the transcript.

## Gate matrix

| Verb | Allowed on | Refused on | Override |
|---|---|---|---|
| `send`   | `idle` (+ L3 end_turn) | everything else | `--force` |
| `cmd`    | `idle` (+ L3 end_turn) | everything else | `--force` (red-tier also needs `--confirm`) |
| `ask`    | `idle` (+ L3 end_turn) | everything else | `--force` |
| `esc`    | `busy`, `modal`, `idle`, `other` | `drafting` only (would wipe human's draft) | `--force` |
| `answer` | `modal` only | everything else | `--force` |
| `self`   | own pane, input box `empty` | input box `drafting` / `modal` / `unknown` | none (allowlist is hard) |
| `wait`   | always (terminal: idle/modal) | — | — |
| `peek` / `tail` / `list` / `status` | always | — | — |

Why the draft protection: `send-keys` *appends* to the tty buffer. If a human has a half-typed draft, your message concatenates with theirs. Every write verb that goes through `safe_to_dm` catches this via the `drafting` state; `esc` applies the same rule explicitly.

## Slash-command tiers (for `cmd`)

| Tier | Commands | Gate |
|------|----------|------|
| 🟢 green | everything else | safety only |
| 🟡 yellow | `/compact` `/loop` `/schedule` | safety only |
| 🔴 red | `/clear` `/exit` `/resume` `/reset` | safety + explicit `--confirm` |

Red tier refuses to send without `--confirm` because those commands are irreversible for the peer.

## Spawning a disposable target for testing

To smoke-test the tool without touching real peers:

```bash
tmux -S /tmp/claude-dm-test.sock -f /dev/null new-session -d -s test -n shell fish
CLAUDE_DM_SOCKET=/tmp/claude-dm-test.sock claude-dm send test:0.0 "hello" --force
tmux -S /tmp/claude-dm-test.sock kill-server   # when done
```

For a full roundtrip with a real Claude, spawn a fresh interactive session in the test socket (costs one session init but minimal tokens until prompted):

```bash
tmux -S /tmp/claude-dm-test.sock -f /dev/null new-session -d -s claude-test -n c 'claude'
```

## Examples

Inspect a peer without touching it:
```bash
claude-dm list
claude-dm peek test:9.1 40
claude-dm status HOME:8.1
```

Trigger a skill on an idle peer:
```bash
claude-dm cmd HOME:6.1 "/compact"
claude-dm cmd HOME:6.1 "/claude-dm"
```

Ask and wait for reply:
```bash
claude-dm ask HOME:8.1 "What's the current test status?" 180
```

Block until a peer finishes its current turn (e.g. after dispatching work via `send`/`cmd`). Pair with `Bash run_in_background` + `Monitor` so the orchestrator agent gets a notification on the sentinel line and decides next steps:
```bash
claude-dm send HOME:8.1 "Run the full test suite and summarise failures."
claude-dm wait HOME:8.1                    # 30s polls, no timeout, blocks until DONE/MODAL
claude-dm wait HOME:8.1 10 600             # 10s polls, give up after 10 min
claude-dm wait HOME:8.1 10 600 60          # also require DONE gate to hold 60s
```
Output is one of:
- `DONE` — peer passes the same gate as `safe_to_dm`: pane title `✳` AND transcript's last assistant turn is `end_turn`. Title-idle alone is not enough; the loop keeps polling while a tool result is still pending so DONE never fires mid-turn.
- `MODAL` — peer hit a permission / AskUserQuestion modal.

The optional 4th arg `debounce_s` suppresses DONE until the gate has held that many consecutive seconds — guards against peers that chain short tool-result turns and would otherwise look transiently DONE between them. Resolution is one poll interval; `debounce_s < interval_s` effectively means "fire on the second consecutive idle poll".

Exit 1 (no stdout sentinel) on timeout or if the peer pane vanishes.

Interrupt a peer that's run too long, or cancel a stuck modal:
```bash
claude-dm esc test:10.2
```

Answer a permission prompt or AskUserQuestion on a peer:
```bash
claude-dm status HOME:6.1           # verify state=modal (permission/question)
claude-dm answer HOME:6.1 1         # pick option 1 (typically "Yes")
claude-dm answer HOME:6.1 2         # option 2 ("Yes, and don't ask again")
claude-dm answer HOME:6.1 3         # option 3 ("No")
```

## Self-DM

Self-trigger a user-only slash command on the current pane:
```bash
claude-dm self /context             # context-window usage summary
claude-dm self "/context all"       # same, but expands per-item
claude-dm self /compact             # pre-emptive compaction before heavy work
claude-dm self /rename              # auto-name session from conversation history
claude-dm self "/rename my-session" # rename to a specific name
```

`self` resolves the current pane via `$TMUX_PANE` and the socket from `$TMUX`.
The synchronous box check up front refuses if a draft or modal is already present
(the same `peer_box_state` check that protects peer DMs).

`self` returns immediately. The slash command fires after the current turn
ends; its output arrives in the next user-turn alongside a
`<notification>claude-dm self /<slash> dispatched; output above</notification>`.
Aborts silently if a draft or modal appears before fire time.

## Audit trail

Every write appends to `~/.claude/claude-dm.log` with timestamp, verb, target, and payload.

## Limitations

- 🔴 **TOCTOU** — peer may enter a modal between check and send; the safety gate is best-effort, not transactional.
- 🔴 **Cross-machine** — not supported directly; tmux socket is local. To address peers on an SSH host or inside a Docker container, build the single-file bundle and run it on the remote: see `portable/README.md`.
- 🟡 **UI drift** — safety checks encode the current Claude Code UI (`✳` glyph, `❯` prompt, `─` rules). Future UI changes may need the regexes updated in `lib/safety.sh`.
- 🟡 **Injection signals as real user** — the peer sees the DM as though the human typed it. Identify yourself in prose messages (`"DM from <your-addr>: …"`) so the peer can reason about trust.
