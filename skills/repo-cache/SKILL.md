---
name: repo-cache
description: >
  Clone or reuse a cached local checkout of a remote git repo (GitHub/GitLab/Bitbucket).
  This skill should be used when the user provides a repo URL or owner/repo identifier
  (e.g. "facebook/react"), says "clone this repo", "read the source", "look at their
  implementation", "study this project", or needs to browse or search across a remote
  codebase.
---

Use this skill when the user points you to a remote git repository (GitHub/GitLab/Bitbucket URLs, `git@...`, or `owner/repo` shorthand).

The goal is to keep a reusable local checkout that is:
- **stable** (predictable path)
- **up to date** (periodic fetch + fast-forward when safe)
- **efficient** (partial clone with `--filter=blob:none`, no repeated full clones)

## Cache location

Repositories are stored at:

`~/.cache/checkouts/<host>/<org>/<repo>`

Example:

`github.com/facebook/react` → `~/.cache/checkouts/github.com/facebook/react`

## Command

```bash
scripts/checkout.sh <repo> --path-only
```

Examples:

```bash
scripts/checkout.sh facebook/react --path-only
scripts/checkout.sh github.com/facebook/react --path-only
scripts/checkout.sh https://github.com/facebook/react --path-only
```

The script will:
1. Parse the repo reference into host/org/repo.
2. Clone if missing.
3. Reuse existing checkout if present.
4. Fetch from `origin` when stale (default interval: 300s).
5. Attempt a fast-forward merge if the checkout is clean and has an upstream.

## Update strategy

- Default behavior is **throttled refresh** (every 5 minutes) to avoid unnecessary network calls.
- Force immediate refresh with:

```bash
scripts/checkout.sh <repo> --force-update --path-only
```

## Recommended workflow

1. Resolve repository path via `checkout.sh --path-only`.
2. Use that path for searching, reading, and analysis.
3. On later references to the same repo, call `checkout.sh` again; it will find and update the cached checkout.

## If edits are needed

Prefer not to edit directly in the shared cache. Create a separate worktree or copy from the cached checkout for task-specific modifications.

## Notes

- `owner/repo` defaults to `github.com`.
