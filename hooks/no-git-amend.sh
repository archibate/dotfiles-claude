#!/usr/bin/bash
# Block destructive git operations (per Claude Code git safety protocol):
#   - git commit --amend            (always create new commits instead)
#   - git push --force / -f         (rewrites remote history)
#   - git push --delete <branch>    (deletes a remote branch)
#   - git push <remote> :<branch>   (refspec form of branch delete)
set -euo pipefail

source "$(dirname "$0")/lib/bypass.sh"
source "$(dirname "$0")/lib/emit.sh"
source "$(dirname "$0")/lib/read_input.sh"
source "$(dirname "$0")/lib/anchors.sh"

read_bash_command

# Each check carries its own bypass marker. Using has_bypass_marker (non-exiting)
# so a BYPASS_AMEND_CHECK does not silence a chained `git push --force`, and
# vice versa.
#
# Anchored to command position via lib/anchors.sh — covers direct invocation
# (with optional sudo flags), `bash -c` / `eval` / `xargs` wrappers, and
# `ssh [opts] host CMD`. Without anchoring, a literal mention like
# `echo "git push --force"` would false-positive.
ANCHORS="(${CMD_ANCHOR_SUDO}|${CMD_WRAPPER}|${CMD_WRAPPER_SSH})"

if echo "$command" | grep -qP "${ANCHORS}git\s+commit\b.*--amend" \
    && ! has_bypass_marker BYPASS_AMEND_CHECK; then
    emit_pre_tool_deny 'Do not use git commit --amend. Always create new commits instead.
If this is a legitimate use, or a false-positive match (e.g. the pattern appears inside a string, comment, or filename, not as an executed command), add comment `# BYPASS_AMEND_CHECK` before the first line of command.'
    exit 0
fi

# git push --force / -f / --force-with-lease / --force-if-includes
if echo "$command" | grep -qP "${ANCHORS}git\s+push\b[^|;&]*(\s--force(-with-lease|-if-includes)?\b|\s-[a-zA-Z]*f\b)" \
    && ! has_bypass_marker BYPASS_FORCE_PUSH_CHECK; then
    emit_pre_tool_deny "Do not use git push --force (or -f). Force-push rewrites remote history and can destroy others' work.
If this is a legitimate use, or a false-positive match (e.g. the pattern appears inside a string, comment, or filename, not as an executed command), add comment \`# BYPASS_FORCE_PUSH_CHECK\` before the first line of command."
    exit 0
fi

# git push --delete / -d <remote> <branch>
# git push <remote> :<branch>  (refspec starting with a colon = delete)
if echo "$command" | grep -qP "${ANCHORS}git\s+push\b[^|;&]*(\s--delete\b|\s-[a-zA-Z]*d\b|\s:[\w./-]+)" \
    && ! has_bypass_marker BYPASS_PUSH_DELETE_CHECK; then
    emit_pre_tool_deny 'Do not use git push --delete (or `git push <remote> :<branch>`). Deleting a remote branch erases history that collaborators may share, and some workflows treat branch refs as a permanent record.
Confirm the branch is fully merged and not protected; prefer letting the remote'"'"'s branch-cleanup workflow handle it after the PR merges.
If this is a legitimate use, or a false-positive match (e.g. the pattern appears inside a string, comment, or filename, not as an executed command), add comment `# BYPASS_PUSH_DELETE_CHECK` before the first line of command.'
    exit 0
fi

exit 0
