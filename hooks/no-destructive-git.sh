#!/usr/bin/bash
# Block destructive git operations that can silently destroy work:
#   - git reset --hard          (discards working-tree and index changes)
#   - git checkout -- / .       (discards working-tree changes for paths)
#   - git restore <path>        (discards working-tree, without --staged)
#   - git clean -f / -fd        (deletes untracked files — may be user WIP)
#   - git branch -D             (force-deletes branch with unmerged commits)
#
# Each check carries its own bypass marker so unrelated chained commands
# don't silence each other.
#
# Companion: no-git-amend.sh covers `git commit --amend`, `git push --force`,
# and `git push --delete`.
set -euo pipefail

source "$(dirname "$0")/lib/bypass.sh"
source "$(dirname "$0")/lib/emit.sh"
source "$(dirname "$0")/lib/read_input.sh"

read_bash_command

# git reset --hard
if echo "$command" | grep -qP 'git\s+reset\b[^|;&]*\s--hard\b' \
    && ! has_bypass_marker BYPASS_RESET_HARD_CHECK; then
    emit_pre_tool_deny 'Do not use git reset --hard. It permanently discards working-tree and index changes.
If you have legitimate reason, add comment `# BYPASS_RESET_HARD_CHECK` before the first line of command.'
    exit 0
fi

# git clean -f (matches combined flags like -fd, -fx, -dfx)
if echo "$command" | grep -qP 'git\s+clean\b[^|;&]*\s-[a-zA-Z]*f[a-zA-Z]*\b' \
    && ! has_bypass_marker BYPASS_GIT_CLEAN_CHECK; then
    emit_pre_tool_deny 'Do not use git clean -f. It deletes untracked files which may include the user'"'"'s in-progress work.
If you have legitimate reason, add comment `# BYPASS_GIT_CLEAN_CHECK` before the first line of command.'
    exit 0
fi

# git branch -D (force-delete; -d alone is non-destructive — it refuses unmerged)
if echo "$command" | grep -qP 'git\s+branch\b[^|;&]*\s-D\b' \
    && ! has_bypass_marker BYPASS_BRANCH_DELETE_CHECK; then
    emit_pre_tool_deny 'Do not use git branch -D. It force-deletes branches with unmerged commits, losing work.
If you have legitimate reason, add comment `# BYPASS_BRANCH_DELETE_CHECK` before the first line of command.'
    exit 0
fi

# git checkout -- <path>  or  git checkout .  (discard working-tree changes)
if echo "$command" | grep -qP 'git\s+checkout\b[^|;&]*(\s--(\s|$)|\s\.(\s|$))' \
    && ! has_bypass_marker BYPASS_CHECKOUT_DISCARD_CHECK; then
    emit_pre_tool_deny 'Do not use git checkout -- / git checkout . — these discard local working-tree changes.
If you have legitimate reason, add comment `# BYPASS_CHECKOUT_DISCARD_CHECK` before the first line of command.'
    exit 0
fi

# git restore <path> WITHOUT --staged / -S (default form discards working-tree changes)
if echo "$command" | grep -qP 'git\s+restore\b' \
    && ! echo "$command" | grep -qP 'git\s+restore\b[^|;&]*\s(--staged|-S)\b' \
    && ! has_bypass_marker BYPASS_RESTORE_CHECK; then
    emit_pre_tool_deny 'Do not use git restore <path> without --staged. It discards working-tree changes.
If you have legitimate reason, add comment `# BYPASS_RESTORE_CHECK` before the first line of command.'
    exit 0
fi

exit 0
