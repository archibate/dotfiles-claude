#!/usr/bin/bash
# Block dangerous system operations. Each check has its own bypass marker so a
# bypass on one chained operation does not silence another.
#
#   - disk format / partition tools  (mkfs, parted, fdisk, gdisk, sgdisk,
#                                     cfdisk, wipefs, cryptsetup luksFormat;
#                                     allowed with --dry-run)
#   - any write to /dev/<device>     (target-based: covers dd of=, redirect,
#                                     tee, cp/mv/install)
#   - any write to /etc, /proc, /sys, /boot
#                                    (system/kernel config; same target-based
#                                     shapes as the /dev/ check)
#   - secure-delete tools            (shred, srm, wipe — irreversible by design)
#   - power-state / kill init        (shutdown, reboot, poweroff, halt,
#                                     init|telinit 0/1/6, systemctl poweroff/
#                                     reboot/halt/kexec, kill -9 1, kill -9 -1)
#   - recursive perm/owner change    (chmod -R, chown -R)
#   - docker prune                   (system/volume/image/container/network)
#   - firewall wipe                  (iptables/ip6tables -F/-X/--flush,
#                                     nft flush ruleset, ufw reset)
#   - crontab -r                     (deletes the user crontab, no prompt)
#   - killall <name>                 (global by-name kill)

set -euo pipefail

source "$(dirname "$0")/lib/bypass.sh"
source "$(dirname "$0")/lib/emit.sh"
source "$(dirname "$0")/lib/read_input.sh"
source "$(dirname "$0")/lib/anchors.sh"

read_bash_command

# Anchored to command position via lib/anchors.sh — covers direct invocation
# (with optional sudo flags), `bash -c` / `eval` / `xargs` wrappers, and
# `ssh [opts] host CMD`. Without anchoring, a literal mention of the tool name
# in a comment, path, or string argument would false-positive.
ANCHORS="(${CMD_ANCHOR_SUDO}|${CMD_WRAPPER}|${CMD_WRAPPER_SSH})"

# ----------------------------------------------------------------------------
# Disk format / partition tools — irrecoverable on wrong target.
# Allow if `--dry-run` is present anywhere in the command.
# ----------------------------------------------------------------------------
if echo "$command" | grep -qP "${ANCHORS}(mkfs(\.[a-zA-Z0-9]+)?|parted|fdisk|gdisk|sgdisk|cfdisk|wipefs)\b" \
    && ! echo "$command" | grep -qP '\-\-dry-run\b' \
    && ! has_bypass_marker BYPASS_DISK_FORMAT_CHECK; then
    emit_pre_tool_deny 'Do not run disk-format / partition-edit tools (mkfs, parted, fdisk, gdisk, sgdisk, cfdisk, wipefs) — formatting or rewriting a partition table is irrecoverable on the wrong target.
Run with `--dry-run` first to preview, and verify the device with `lsblk -f` (confirm size matches the user'"'"'s expected disk and no partition is mounted).
If this is a legitimate use, or a false-positive match (e.g. the pattern appears inside a string, comment, or filename, not as an executed command), add comment `# BYPASS_DISK_FORMAT_CHECK` before the first line of command.'
    exit 0
fi

if echo "$command" | grep -qP "${ANCHORS}cryptsetup\b[^|;&]*\b(luksFormat|erase|reencrypt)\b" \
    && ! echo "$command" | grep -qP '\-\-dry-run\b' \
    && ! has_bypass_marker BYPASS_DISK_FORMAT_CHECK; then
    emit_pre_tool_deny 'Do not run cryptsetup luksFormat / erase / reencrypt — these destroy the LUKS header or rewrite the encrypted volume; lost headers are unrecoverable without an external backup.
Back up the header first (`cryptsetup luksHeaderBackup`) and verify the device with `lsblk -f`.
If this is a legitimate use, or a false-positive match (e.g. the pattern appears inside a string, comment, or filename, not as an executed command), add comment `# BYPASS_DISK_FORMAT_CHECK` before the first line of command.'
    exit 0
fi

# ----------------------------------------------------------------------------
# Write to /dev/<device> — target-based, not tool-based.
# Allowed pseudo-devices: null, zero, random, urandom, full, console,
# stderr/stdout/stdin, ptmx, tty* (terminals/serial), fd/*, pts/*.
# Reads (`cat /dev/sda`, `dd if=/dev/sda of=img`) are NOT blocked.
# Four shapes: of=, >/>>, tee, cp|mv|install (only when path is the LAST arg).
# ----------------------------------------------------------------------------
# `(?![/.\w])` after each safe name means "not followed by path-continuation"
# — rejects `/dev/null/../sda`, `/dev/null2`, `/dev/null/sub`, etc.
SAFE_DEV='(?!(null|zero|random|urandom|full|console|stderr|stdout|stdin|ptmx)(?![/.\w])|tty\w*(?![/.\w])|fd/\w+(?![/.\w])|pts/\w+(?![/.\w]))'
if (echo "$command" | grep -qP "\bof=/dev/${SAFE_DEV}\S" \
    || echo "$command" | grep -qP ">>?\s*/dev/${SAFE_DEV}\S" \
    || echo "$command" | grep -qP "\btee\b[^|;&]*\s/dev/${SAFE_DEV}\S" \
    || echo "$command" | grep -qP "\b(cp|mv|install)\b[^|;&]*\s/dev/${SAFE_DEV}\S+\s*(\$|[|;&])") \
    && ! has_bypass_marker BYPASS_BLOCKDEV_WRITE_CHECK; then
    emit_pre_tool_deny 'Do not write to a /dev/<device>. The hazard is the target, not the tool — `dd of=`, `> /dev/X`, `tee /dev/X`, and `cp/mv/install … /dev/X` all share the same failure mode: one wrong letter overwrites a live disk. Switching tools does not make it safer.
Verify with `lsblk -f` that the device path is correct and no partition is mounted; confirm the size matches the user'"'"'s expected disk before bypassing.
If this is a legitimate use, or a false-positive match (e.g. the pattern appears inside a string, comment, or filename, not as an executed command), add comment `# BYPASS_BLOCKDEV_WRITE_CHECK` before the first line of command.'
    exit 0
fi

# ----------------------------------------------------------------------------
# Write to /etc, /proc, /sys, /boot — system/kernel config.
# Same four shapes as the /dev/ check. Catches `echo X > /proc/sysrq-trigger`,
# `tee /etc/passwd`, `dd of=/sys/...`, `cp config /etc/...`, etc.
# Non-root invocations will fail with EACCES — that is fine; we still flag the
# pattern so accidents do not slip through if Claude is running privileged.
# ----------------------------------------------------------------------------
SYS_PATH='(/etc|/proc|/sys|/boot)/'
if (echo "$command" | grep -qP "\bof=${SYS_PATH}\S" \
    || echo "$command" | grep -qP ">>?\s*${SYS_PATH}\S" \
    || echo "$command" | grep -qP "\btee\b[^|;&]*\s${SYS_PATH}\S" \
    || echo "$command" | grep -qP "\b(cp|mv|install)\b[^|;&]*\s${SYS_PATH}\S+\s*(\$|[|;&])") \
    && ! has_bypass_marker BYPASS_SYSPATH_WRITE_CHECK; then
    emit_pre_tool_deny 'Do not write to /etc, /proc, /sys, or /boot. These paths control system/kernel state — one bad write can break boot, networking, login, or kernel parameters. The hazard is the target, not the tool.
For /etc edits prefer `sudoedit`. For kernel params prefer `sysctl -w net.foo=bar` over raw `> /proc/sys/...`. Confirm the exact path with `ls -l` and the change with the user before bypassing.
If this is a legitimate use, or a false-positive match (e.g. the pattern appears inside a string, comment, or filename, not as an executed command), add comment `# BYPASS_SYSPATH_WRITE_CHECK` before the first line of command.'
    exit 0
fi

# ----------------------------------------------------------------------------
# Secure-delete tools — `shred`, `srm`, `wipe`. Irreversible by design.
# Anchored to command position via lib/anchors.sh so the check fires only when
# the tool is actually invoked — comments, paths containing the substring
# (e.g. `/tmp/srm-cache`), and arguments mentioning the word (e.g.
# `echo "do not srm"`) no longer false-positive.
# `wipefs` is a different tool (handled in the disk-format check above) —
# CMD_TRAIL requires a separator after `wipe`, so `wipefs` cannot match here.
# Includes CMD_WRAPPER_SSH because remote secure-erase (`ssh host srm /x`)
# destroys data just as irrecoverably as a local one.
# ----------------------------------------------------------------------------
if echo "$command" | grep -qP "${ANCHORS}(shred|srm|wipe)${CMD_TRAIL}" \
    && ! has_bypass_marker BYPASS_SECURE_DELETE_CHECK; then
    emit_pre_tool_deny 'Do not use shred / srm / wipe — secure-erase tools destroy data with no recovery path. Filesystem-level snapshots, journals, and backups cannot recover what these tools overwrite.
Plain `rm` (or `trash`) is reversible from snapshots/backups in most environments. Only use secure-erase when you have a documented compliance requirement.
If this is a legitimate use, or a false-positive match (e.g. the pattern appears inside a string, comment, or filename, not as an executed command), add comment `# BYPASS_SECURE_DELETE_CHECK` before the first line of command.'
    exit 0
fi

# ----------------------------------------------------------------------------
# Power-state operations — terminate the host. Catastrophic on shared/remote
# machines. Includes shutdown/reboot/poweroff/halt, init|telinit 0/1/6,
# systemctl power verbs, and kill -9 1 (init) / kill -9 -1 (every owned PID).
# ----------------------------------------------------------------------------
if (echo "$command" | grep -qP "${ANCHORS}(shutdown|reboot|poweroff|halt)\b" \
    || echo "$command" | grep -qP "${ANCHORS}(tel)?init\s+[016]\b" \
    || echo "$command" | grep -qP "${ANCHORS}systemctl\s+(poweroff|reboot|halt|kexec|hibernate|suspend)\b" \
    || echo "$command" | grep -qP "${ANCHORS}kill\s+(-9|-KILL|-SIGKILL)\s+-?1\b") \
    && ! has_bypass_marker BYPASS_POWER_STATE_CHECK; then
    emit_pre_tool_deny 'Do not change the host power state (shutdown / reboot / poweroff / halt / init 0|1|6 / systemctl poweroff|reboot|halt|kexec / kill -9 1) — these terminate the host and on remote/shared machines you may have no way back in.
Confirm hostname with `hostname` and `who` for other logged-in users before bypassing; for service restarts prefer `systemctl restart <unit>` instead.
If this is a legitimate use, or a false-positive match (e.g. the pattern appears inside a string, comment, or filename, not as an executed command), add comment `# BYPASS_POWER_STATE_CHECK` before the first line of command.'
    exit 0
fi

# ----------------------------------------------------------------------------
# Recursive permission/ownership change — chmod -R / chown -R.
# Matches `-R`, `-Rf`, `-fR`, `-vR`, etc. (combined short flags).
# ----------------------------------------------------------------------------
if echo "$command" | grep -qP "${ANCHORS}(chmod|chown)\b[^|;&]*\s-[a-zA-Z]*R[a-zA-Z]*\b" \
    && ! has_bypass_marker BYPASS_RECURSIVE_PERMS_CHECK; then
    emit_pre_tool_deny 'Do not use chmod -R / chown -R. Recursive permission or ownership changes silently rewrite metadata for every file in the tree — one wrong path can lock out a user, break system services, or corrupt package-manager invariants.
Test on a single file first, scope the recursion to the smallest possible subtree, and never recurse from `/` or `$HOME`. Consider `find <dir> -type f -exec chmod 644 {} +` for filtered changes.
If this is a legitimate use, or a false-positive match (e.g. the pattern appears inside a string, comment, or filename, not as an executed command), add comment `# BYPASS_RECURSIVE_PERMS_CHECK` before the first line of command.'
    exit 0
fi

# ----------------------------------------------------------------------------
# Docker prune — wipes containers / volumes / images / networks; volume prune
# in particular discards data volumes that may be the only copy.
# ----------------------------------------------------------------------------
if echo "$command" | grep -qP "${ANCHORS}docker\s+(system|volume|image|container|network)\s+prune\b" \
    && ! has_bypass_marker BYPASS_DOCKER_PRUNE_CHECK; then
    emit_pre_tool_deny 'Do not run docker {system,volume,image,container,network} prune. Pruning removes resources without confirmation; volume prune discards data volumes that may be the only copy of stateful container data.
List candidates first (`docker volume ls -f dangling=true`, `docker ps -a --filter status=exited`) and remove specific items by name.
If this is a legitimate use, or a false-positive match (e.g. the pattern appears inside a string, comment, or filename, not as an executed command), add comment `# BYPASS_DOCKER_PRUNE_CHECK` before the first line of command.'
    exit 0
fi

# ----------------------------------------------------------------------------
# Firewall wipe — locks you out of remote machines instantly.
#   iptables/ip6tables -F | -X | --flush | --delete-chain
#   nft flush ruleset
#   ufw [--force] reset
# ----------------------------------------------------------------------------
if (echo "$command" | grep -qP "${ANCHORS}ip6?tables\b[^|;&]*\s(-[a-zA-Z]*[FX][a-zA-Z]*\b|--flush\b|--delete-chain\b)" \
    || echo "$command" | grep -qP "${ANCHORS}nft\s+flush\s+ruleset\b" \
    || echo "$command" | grep -qP "${ANCHORS}ufw\s+(--force\s+)?reset\b") \
    && ! has_bypass_marker BYPASS_FIREWALL_WIPE_CHECK; then
    emit_pre_tool_deny 'Do not flush firewall rules. `iptables -F`, `nft flush ruleset`, and `ufw reset` can lock you out of remote machines instantly — the SSH session itself relies on the rules you are about to remove.
Save current rules first (`iptables-save > /tmp/rules.bak`) and schedule a revert (`echo iptables-restore < /tmp/rules.bak | at now+5min`) before flushing.
If this is a legitimate use, or a false-positive match (e.g. the pattern appears inside a string, comment, or filename, not as an executed command), add comment `# BYPASS_FIREWALL_WIPE_CHECK` before the first line of command.'
    exit 0
fi

# ----------------------------------------------------------------------------
# crontab -r — deletes the entire user crontab with no prompt and no backup.
# ----------------------------------------------------------------------------
if echo "$command" | grep -qP "${ANCHORS}crontab\b[^|;&]*\s(-[a-zA-Z]*r[a-zA-Z]*|--remove)\b" \
    && ! has_bypass_marker BYPASS_CRONTAB_REMOVE_CHECK; then
    emit_pre_tool_deny 'Do not run `crontab -r`. It deletes the entire user crontab with no confirmation and no backup.
Run `crontab -l > backup.cron` first, then `crontab -e` to remove specific entries.
If this is a legitimate use, or a false-positive match (e.g. the pattern appears inside a string, comment, or filename, not as an executed command), add comment `# BYPASS_CRONTAB_REMOVE_CHECK` before the first line of command.'
    exit 0
fi

# ----------------------------------------------------------------------------
# killall — global by-name process kill across all users/sessions.
# ----------------------------------------------------------------------------
if echo "$command" | grep -qP "${ANCHORS}killall\b" \
    && ! has_bypass_marker BYPASS_KILLALL_CHECK; then
    emit_pre_tool_deny 'Do not use `killall` — it kills every matching process system-wide, including unrelated ones from other users or sessions.
Safer: `pgrep -af <pattern>` first to see exactly which PIDs match, then `kill <PID>` for the specific target. Or `pkill -f <pattern>` when the full command-line pattern is unique.
If this is a legitimate use, or a false-positive match (e.g. the pattern appears inside a string, comment, or filename, not as an executed command), add comment `# BYPASS_KILLALL_CHECK` before the first line of command.'
    exit 0
fi

exit 0
