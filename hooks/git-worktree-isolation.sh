#!/usr/bin/env bash
set -euo pipefail

mode=${1:-}
input=$(cat)

json_get() {
  local expr=$1
  jq -r "$expr // empty" <<<"$input"
}

cwd=$(json_get '.cwd // .currentWorkingDirectory // .workspace.cwd // .workspace.current_dir // .originalCwd // .project_dir')
if [ -z "$cwd" ] || [ ! -d "$cwd" ]; then
  cwd=$PWD
fi

slugify() {
  tr '/[:space:]' '--' | tr -cd 'A-Za-z0-9._-' | cut -c1-48
}

repo_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)
if [ -z "$repo_root" ]; then
  echo "git-worktree-isolation: $cwd is not inside a git repository" >&2
  exit 1
fi

case "$mode" in
  create)
    requested_name=$(json_get '.name // .worktreeName // .slug')
    if [ -z "$requested_name" ]; then
      requested_name="claude-$(date +%Y%m%d-%H%M%S)-$$"
    fi
    safe_name=$(printf '%s' "$requested_name" | slugify)
    if [ -z "$safe_name" ]; then
      safe_name="claude-$(date +%Y%m%d-%H%M%S)-$$"
    fi

    worktree_parent="$repo_root/.claude/worktrees"
    mkdir -p "$worktree_parent"
    worktree_path="$worktree_parent/$safe_name"
    if [ -e "$worktree_path" ]; then
      worktree_path="$worktree_parent/$safe_name-$$"
    fi

    current_branch=$(git -C "$repo_root" branch --show-current 2>/dev/null || true)
    if [ -z "$current_branch" ]; then
      current_branch="detached"
    fi
    branch="claude/$safe_name"
    if git -C "$repo_root" show-ref --verify --quiet "refs/heads/$branch"; then
      branch="claude/$safe_name-$$"
    fi

    base_ref=$(json_get '.baseRef')
    if [ "$base_ref" = "fresh" ]; then
      remote_head=$(git -C "$repo_root" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)
      if [ -n "$remote_head" ]; then
        git -C "$repo_root" worktree add -b "$branch" "$worktree_path" "$remote_head" >/dev/null
      else
        git -C "$repo_root" worktree add -b "$branch" "$worktree_path" HEAD >/dev/null
      fi
    else
      git -C "$repo_root" worktree add -b "$branch" "$worktree_path" HEAD >/dev/null
    fi

    jq -n --arg path "$worktree_path" --arg branch "$branch" '{hookSpecificOutput:{hookEventName:"WorktreeCreate", worktreePath:$path, worktreeBranch:$branch}, worktreePath:$path, worktreeBranch:$branch}'
    ;;
  remove)
    worktree_path=$(json_get '.worktreePath // .path')
    if [ -z "$worktree_path" ]; then
      echo "git-worktree-isolation: missing worktreePath" >&2
      exit 1
    fi
    git -C "$repo_root" worktree remove --force "$worktree_path" >/dev/null
    jq -n '{hookSpecificOutput:{hookEventName:"WorktreeRemove"}}'
    ;;
  *)
    echo "usage: git-worktree-isolation.sh create|remove" >&2
    exit 2
    ;;
esac
