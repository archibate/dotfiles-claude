#!/usr/bin/bash
# Shared bypass-marker helpers for PreToolUse hooks.
#
# After `set -euo pipefail` and `read_bash_command`:
#
#   bypass_check BYPASS_FOO_CHECK     # exits 0 if marker present
#   has_bypass_marker BYPASS_FOO_CHECK # returns 0/1; non-exiting
#
# The marker matches anywhere in $command. Convention is the user places it as
# a comment on the first line of the command, but lenient matching makes it
# robust to multi-line scripts and trailing `# BYPASS_X` comments.

bypass_check() {
    if echo "$command" | grep -qF "$1"; then
        exit 0
    fi
}

# has_bypass_marker MARKER — non-exiting variant.
# Returns 0 if MARKER appears anywhere in $command, 1 otherwise.
# Use this in hooks with multiple independent checks that each carry their
# own marker (e.g. no-git-amend: amend bypass must not silence force-push).
has_bypass_marker() {
    echo "$command" | grep -qF "$1"
}
