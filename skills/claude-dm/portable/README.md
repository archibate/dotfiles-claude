# portable-claude-dm

A single-file build of `claude-dm` for use over SSH. The dispatcher and all four
lib files are concatenated into one self-contained bash script with no
filesystem layout dependency, so it can be rsynced to any host and invoked
remotely.

## Why this exists

The skill's normal layout (`bin/claude-dm` + `lib/*.sh` sourced via `$HERE`) is
fine for the local box but inconvenient to install elsewhere. The portable
bundle inlines everything, runs a dependency check up front, and embeds the
build commit so you can verify what's deployed.

`claude-dm` itself is local-only by design (the `pid → sessionId → transcript`
chain assumes same-host filesystem). Cross-machine messaging works by running
the bundle *on the remote host* — local Claude orchestrates via `ssh vm
portable-claude-dm …`, and all pid/socket/transcript lookups happen where the
remote tmux + Claude actually live.

## Build

```bash
./portable/build-portable.sh
```

Produces `portable/portable-claude-dm`. The script also runs `bash -n` on the
result and aborts on syntax failure. The build commit sha appears on line 2 of
the output (`head -2 portable/portable-claude-dm`).

The build uses a `# BEGIN_DISPATCHER` sentinel in `bin/claude-dm` to know where
the include block ends — moving lines around there is safe as long as the
sentinel survives.

## Deploy

```bash
rsync portable/portable-claude-dm vm:.local/bin/
```

Or, if you don't want to add to PATH:

```bash
scp portable/portable-claude-dm vm:/tmp/
ssh vm /tmp/portable-claude-dm list
```

The remote needs: `tmux jq awk sed pgrep ps find tr wc head tail cat grep stat
date sleep cp`. The bundle's preamble fails fast with `missing dep: <name>` if
anything is absent.

## Use

```bash
ssh vm portable-claude-dm list
ssh vm portable-claude-dm status HOME:0.0
ssh vm portable-claude-dm send HOME:0.0 'continue the test run' --force
ssh vm portable-claude-dm ask  HOME:0.0 'what step are you on?' 180
```

### Docker container

Same pattern, with `docker cp` + `docker exec` replacing `rsync` + `ssh`. The
container must (a) be running its own tmux server with at least one Claude
Code pane and (b) have the dependencies listed above. The bundle resolves
panes via the in-container tmux socket — there is no host/container bridging,
so peers visible from inside the container are the only addressable ones.

```bash
docker cp portable/portable-claude-dm CONTAINER:/usr/local/bin/portable-claude-dm
docker exec CONTAINER portable-claude-dm list
docker exec CONTAINER portable-claude-dm send work:0.0 'resume' --force
```

If `pgrep` / `ps` is missing in a stripped container image, the dep-check
preamble will fail fast with `missing dep: <name>` — install `procps` (or
distro equivalent) and retry.

### Latency tuning (SSH)

For chatty sessions, enable an SSH ControlMaster in
`~/.ssh/config`:

```
Host vm
  ControlMaster auto
  ControlPath /tmp/cm-%r@%h:%p
  ControlPersist 60s
```

## Caveats

- **Audit log lands on remote.** Each DM appends to
  `~/.claude/claude-dm.log` on the host where it was sent, which is the remote.
  If you want a local trail of "I dispatched X to vm", wrap the call in a
  shell function that tees a record on your side.
- **Version drift.** The build sha header is the only signal that local source
  ≠ remote bundle. Rebuild + rsync after editing `lib/` or `bin/`.
- **`safe_to_dm` is UI-version-coupled.** The pane-state regexes match the
  Claude Code TUI version that was current when the skill was authored. If the
  remote runs a much newer (or older) Claude Code with different glyphs / box
  characters, state detection may misclassify.
- **`self` verb is meaningless cross-machine.** Calling `ssh vm
  portable-claude-dm self /compact` runs in a non-tmux SSH session on the
  remote and exits silently — `self` only works from inside a Claude Code
  pane on its own host.
- **`tests/` not bundled.** The skill's local tests run against the source
  tree, not the bundle. To smoke-test the bundle on a remote, just call
  `portable-claude-dm list` after deploy.
