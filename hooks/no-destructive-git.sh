#!/usr/bin/bash
# Block destructive git operations that can silently destroy work:
#   - git reset --hard          (discards working-tree and index changes)
#   - git checkout -- / .       (discards working-tree changes for paths)
#   - git restore <path>        (discards working-tree, without --staged)
#   - git clean -f / -fd        (deletes untracked files — may be user WIP)
#   - git branch -D             (force-deletes branch with unmerged commits)
#   - git rm -f                 (overrides the safety check that refuses to
#                                delete files with uncommitted changes;
#                                bare `git rm` is safe — git refuses, and
#                                committed content is recoverable from history)
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
source "$(dirname "$0")/lib/anchors.sh"

read_bash_command

# Anchored to command position via lib/anchors.sh — covers direct invocation
# (with optional sudo flags), `bash -c` / `eval` / `xargs` wrappers, and
# `ssh [opts] host CMD`. Without anchoring, a literal mention like
# `echo "git reset --hard"` would false-positive.
ANCHORS="(${CMD_ANCHOR_SUDO}|${CMD_WRAPPER}|${CMD_WRAPPER_SSH})"

# git reset --hard
if echo "$command" | grep -qP "${ANCHORS}git\s+reset\b[^|;&]*\s--hard\b" \
    && ! has_bypass_marker BYPASS_RESET_HARD_CHECK; then
    emit_pre_tool_deny 'Do not use git reset --hard. It permanently discards working-tree and index changes.
If this is a legitimate use, or a false-positive match (e.g. the pattern appears inside a string, comment, or filename, not as an executed command), add comment `# BYPASS_RESET_HARD_CHECK` before the first line of command.'
    exit 0
fi

# git clean -f (matches combined flags like -fd, -fx, -dfx)
if echo "$command" | grep -qP "${ANCHORS}git\s+clean\b[^|;&]*\s-[a-zA-Z]*f[a-zA-Z]*\b" \
    && ! has_bypass_marker BYPASS_GIT_CLEAN_CHECK; then
    emit_pre_tool_deny 'Do not use git clean -f. It deletes untracked files which may include the user'"'"'s in-progress work.
If this is a legitimate use, or a false-positive match (e.g. the pattern appears inside a string, comment, or filename, not as an executed command), add comment `# BYPASS_GIT_CLEAN_CHECK` before the first line of command.'
    exit 0
fi

# git branch -D (force-delete; -d alone is non-destructive — it refuses unmerged)
if echo "$command" | grep -qP "${ANCHORS}git\s+branch\b[^|;&]*\s-D\b" \
    && ! has_bypass_marker BYPASS_BRANCH_DELETE_CHECK; then
    emit_pre_tool_deny 'Do not use git branch -D. It force-deletes branches with unmerged commits, losing work.
If this is a legitimate use, or a false-positive match (e.g. the pattern appears inside a string, comment, or filename, not as an executed command), add comment `# BYPASS_BRANCH_DELETE_CHECK` before the first line of command.'
    exit 0
fi

# git checkout -- <path>  or  git checkout .  (discard working-tree changes)
if echo "$command" | grep -qP "${ANCHORS}git\s+checkout\b[^|;&]*(\s--(\s|$)|\s\.(\s|$))" \
    && ! has_bypass_marker BYPASS_CHECKOUT_DISCARD_CHECK; then
    emit_pre_tool_deny 'Do not use git checkout -- / git checkout . — these discard local working-tree changes.
If this is a legitimate use, or a false-positive match (e.g. the pattern appears inside a string, comment, or filename, not as an executed command), add comment `# BYPASS_CHECKOUT_DISCARD_CHECK` before the first line of command.'
    exit 0
fi

# git restore <path> WITHOUT --staged / -S (default form discards working-tree changes)
if echo "$command" | grep -qP "${ANCHORS}git\s+restore\b" \
    && ! echo "$command" | grep -qP 'git\s+restore\b[^|;&]*\s(--staged|-S)\b' \
    && ! has_bypass_marker BYPASS_RESTORE_CHECK; then
    emit_pre_tool_deny 'Do not use git restore <path> without --staged. It discards working-tree changes.
If this is a legitimate use, or a false-positive match (e.g. the pattern appears inside a string, comment, or filename, not as an executed command), add comment `# BYPASS_RESTORE_CHECK` before the first line of command.'
    exit 0
fi

# git rm -f / --force (overrides safety check on uncommitted changes)
# Plain `git rm` is safe: git refuses to delete files with uncommitted
# modifications, and committed content is always recoverable from history.
# `--cached` is also safe — it only unstages, doesn't touch the filesystem,
# so `git rm --cached -f` is exempted from this check.
if echo "$command" | grep -qP "${ANCHORS}git\s+rm\b[^|;&]*\s(-[a-zA-Z]*f[a-zA-Z]*|--force)\b" \
    && ! echo "$command" | grep -qP 'git\s+rm\b[^|;&]*\s--cached\b' \
    && ! has_bypass_marker BYPASS_GIT_RM_FORCE_CHECK; then
    emit_pre_tool_deny 'Do not use git rm -f / --force. It overrides git'"'"'s safety check and deletes files with uncommitted modifications — those changes are then unrecoverable (git only has the last committed version).
Plain `git rm <file>` refuses uncommitted changes (safe). If you intend to discard those modifications, commit / stash them first, then `git rm`.
If this is a legitimate use, or a false-positive match (e.g. the pattern appears inside a string, comment, or filename, not as an executed command), add comment `# BYPASS_GIT_RM_FORCE_CHECK` before the first line of command.'
    exit 0
fi

exit 0
