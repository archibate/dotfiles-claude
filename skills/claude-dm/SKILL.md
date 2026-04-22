---
name: claude-dm
description: >
  Peer-to-peer messaging between Claude Code sessions sharing a tmux server:
  list sessions, peek their last reply, DM prose or slash commands, ask and
  wait for a reply, interrupt a stuck peer, or answer a peer's permission
  modal. Use when coordinating multiple simultaneous Claude sessions — e.g.
  "dm another claude", "list claude sessions", "stop another claude",
  "answer the permission prompt on peer X", "orchestrate claude sessions".
---

# claude-dm

Peer-to-peer messaging between independent Claude Code sessions that share a tmux server.

## When to use

- Multiple Claude Code sessions are running on the same machine (check with `list`), and one needs to inspect or communicate with another.
- You need to know what another Claude is currently working on, without attaching to its tmux pane.
- You want to trigger a slash command (`/compact`, `/re-read`, etc.) in another session.
- Send a prompt to a peer and wait for the reply as data.

## When NOT to use

- To spawn a child Claude for one-shot work → use the `Agent` tool.
- To schedule a future Claude run on the cloud → use the `schedule` skill or `RemoteTrigger`.
- To send a message to another *user's* Claude on a different machine → this skill can't.

## Prerequisites

- Peers must run in tmux (any socket). Default resolution: `$CLAUDE_DM_SOCKET` or `/tmp/tmux-$(id -u)/default`.
- Same Unix user (or a shared socket with group perms).
- `tmux`, `jq`, `awk`, `sed`, `pgrep` in `$PATH` (all present on this box).

## Verbs

```
claude-dm list                                 # roster of claude panes
claude-dm status <target>                      # state + safety gate result
claude-dm peek   <target> [N]                  # last N text blocks of peer's transcript
claude-dm tail   <target>                      # live-follow peer's JSONL
claude-dm send   <target> <msg>   [--force]
claude-dm cmd    <target> /<slash> [--force] [--confirm]
claude-dm ask    <target> <msg>   [timeout_s]
claude-dm esc    <target>          [--force]   # Escape: interrupt turn or cancel modal
claude-dm answer <target> <key>    [--force]   # pick modal option (1/2/3/y/n/a/…)
```

`<target>` is `session:window.pane` on the current socket (e.g. `CC:8.1`).

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
claude-dm peek rql2:9.1 40
claude-dm status CC:8.1
```

Trigger a skill on an idle peer:
```bash
claude-dm cmd CC:6.1 "/compact"
claude-dm cmd CC:6.1 "/re-read"
```

Ask and wait for reply:
```bash
claude-dm ask CC:8.1 "What's the current test status?" 180
```

Interrupt a peer that's run too long, or cancel a stuck modal:
```bash
claude-dm esc rql2:10.2
```

Answer a permission prompt or AskUserQuestion on a peer:
```bash
claude-dm status CC:6.1           # verify state=modal (permission/question)
claude-dm answer CC:6.1 1         # pick option 1 (typically "Yes")
claude-dm answer CC:6.1 2         # option 2 ("Yes, and don't ask again")
claude-dm answer CC:6.1 3         # option 3 ("No")
```

## Audit trail

Every write appends to `~/.claude/claude-dm.log` with timestamp, verb, target, and payload.

## Limitations

- 🔴 **TOCTOU** — peer may enter a modal between check and send; the safety gate is best-effort, not transactional.
- 🔴 **Cross-machine** — not supported; tmux socket is local. Wrap with `ssh host tmux …` if you really need it.
- 🟡 **UI drift** — safety checks encode the current Claude Code UI (`✳` glyph, `❯` prompt, `─` rules). Future UI changes may need the regexes updated in `lib/safety.sh`.
- 🟡 **Injection signals as real user** — the peer sees the DM as though the human typed it. Identify yourself in prose messages (`"DM from <your-addr>: …"`) so the peer can reason about trust.
