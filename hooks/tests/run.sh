#!/usr/bin/bash
# Test harness for migrated hooks. Deliberately contains trigger patterns;
# hooks see only the outer `bash /tmp/hook-test.sh` invocation.

# Scrub env that some hooks consult, so tests reproduce the hook behavior a
# fresh user environment would see (Claude's runtime env can set
# PYTHONUNBUFFERED, masking deny tests).
unset PYTHONUNBUFFERED

fail=0

assert_deny() {
  local name="$1" input="$2" pattern="$3"
  local out
  out=$(printf '%s' "$input" | bash ~/.claude/hooks/$name.sh 2>&1)
  # jq -e returns 0 on empty stdin, so guard explicitly — otherwise a silent
  # hook would falsely pass an assert_deny check.
  if [ -z "$out" ] || ! echo "$out" | jq -e ".hookSpecificOutput.permissionDecision == \"deny\" and (.hookSpecificOutput.permissionDecisionReason | contains(\"$pattern\"))" > "$test_out"; then
    echo "FAIL: $name should deny with pattern '$pattern'"
    echo "  got: $out"
    fail=1
  else
    echo "OK:   $name deny ($pattern)"
  fi
}

assert_silent() {
  local name="$1" input="$2"
  local out
  out=$(printf '%s' "$input" | bash ~/.claude/hooks/$name.sh 2>&1)
  if [ -n "$out" ]; then
    echo "FAIL: $name should be silent"
    echo "  got: $out"
    fail=1
  else
    echo "OK:   $name silent"
  fi
}

assert_context() {
  local name="$1" input="$2" pattern="$3"
  local out
  out=$(printf '%s' "$input" | bash ~/.claude/hooks/$name.sh 2>&1)
  if ! echo "$out" | jq -e ".hookSpecificOutput.additionalContext | contains(\"$pattern\")" > "$test_out"; then
    echo "FAIL: $name should emit additionalContext containing '$pattern'"
    echo "  got: $out"
    fail=1
  else
    echo "OK:   $name context ($pattern)"
  fi
}

test_out=$(mktemp)

echo "=== PreToolUse no-* hooks ==="

# Concatenate the forbidden strings at runtime so this test file doesn't itself trigger outer hooks
AMP='&'
REDIR='>'
DEV="/dev/null"

assert_deny no-devnull-redirect "$(jq -n --arg c "ls ${REDIR}${DEV}" '{tool_input:{command:$c}}')" "${DEV}"
assert_silent no-devnull-redirect '{"tool_input":{"command":"ls"}}'

assert_deny no-background-ampersand "$(jq -n --arg c "sleep 10 ${AMP}" '{tool_input:{command:$c}}')" "background execution"
assert_silent no-background-ampersand '{"tool_input":{"command":"ls && echo ok"}}'

assert_deny no-git-amend "$(jq -n --arg c "git commit --amend" '{tool_input:{command:$c}}')" "git commit --amend"
assert_deny no-git-amend "$(jq -n --arg c "git push --force" '{tool_input:{command:$c}}')" "push --force"
assert_silent no-git-amend '{"tool_input":{"command":"git status"}}'

# no-destructive-git: each destructive operation has its own bypass marker
assert_deny no-destructive-git '{"tool_input":{"command":"git reset --hard HEAD~1"}}' "reset --hard"
assert_deny no-destructive-git '{"tool_input":{"command":"git clean -fd"}}' "git clean -f"
assert_deny no-destructive-git '{"tool_input":{"command":"git clean -f"}}' "git clean -f"
assert_deny no-destructive-git '{"tool_input":{"command":"git branch -D feature-x"}}' "branch -D"
assert_deny no-destructive-git '{"tool_input":{"command":"git checkout -- foo.py"}}' "checkout --"
assert_deny no-destructive-git '{"tool_input":{"command":"git checkout ."}}' "checkout --"
assert_deny no-destructive-git '{"tool_input":{"command":"git checkout main -- foo.py"}}' "checkout --"
assert_deny no-destructive-git '{"tool_input":{"command":"git restore foo.py"}}' "git restore"
# Safe forms — silent
assert_silent no-destructive-git '{"tool_input":{"command":"git status"}}'
assert_silent no-destructive-git '{"tool_input":{"command":"git reset HEAD~1"}}'
assert_silent no-destructive-git '{"tool_input":{"command":"git checkout main"}}'
assert_silent no-destructive-git '{"tool_input":{"command":"git checkout -b feature"}}'
assert_silent no-destructive-git '{"tool_input":{"command":"git branch -d merged-feature"}}'
assert_silent no-destructive-git '{"tool_input":{"command":"git restore --staged foo.py"}}'
assert_silent no-destructive-git '{"tool_input":{"command":"git clean -n"}}'
# Bypass markers silence their own check only
assert_silent no-destructive-git '{"tool_input":{"command":"# BYPASS_RESET_HARD_CHECK\ngit reset --hard HEAD~1"}}'
assert_silent no-destructive-git '{"tool_input":{"command":"# BYPASS_GIT_CLEAN_CHECK\ngit clean -fd"}}'
assert_silent no-destructive-git '{"tool_input":{"command":"# BYPASS_BRANCH_DELETE_CHECK\ngit branch -D feature"}}'
assert_silent no-destructive-git '{"tool_input":{"command":"# BYPASS_CHECKOUT_DISCARD_CHECK\ngit checkout -- foo.py"}}'
assert_silent no-destructive-git '{"tool_input":{"command":"# BYPASS_RESTORE_CHECK\ngit restore foo.py"}}'
# Reset bypass must not silence chained clean -fd
assert_deny no-destructive-git '{"tool_input":{"command":"# BYPASS_RESET_HARD_CHECK\ngit reset --hard; git clean -fd"}}' "git clean -f"

# git rm -f / --force — destroys uncommitted changes irrecoverably
assert_deny no-destructive-git '{"tool_input":{"command":"git rm -f foo.py"}}' "git rm -f"
assert_deny no-destructive-git '{"tool_input":{"command":"git rm --force foo.py"}}' "git rm -f"
assert_deny no-destructive-git '{"tool_input":{"command":"git rm -rf src/"}}' "git rm -f"
assert_deny no-destructive-git '{"tool_input":{"command":"git rm -fr src/"}}' "git rm -f"
# Bare git rm — safe (refuses uncommitted; committed content recoverable)
assert_silent no-destructive-git '{"tool_input":{"command":"git rm foo.py"}}'
assert_silent no-destructive-git '{"tool_input":{"command":"git rm -r src/"}}'
# --cached only unstages, so -f is safe in that context
assert_silent no-destructive-git '{"tool_input":{"command":"git rm --cached foo.py"}}'
assert_silent no-destructive-git '{"tool_input":{"command":"git rm --cached -f foo.py"}}'
assert_silent no-destructive-git '{"tool_input":{"command":"git rm -f --cached foo.py"}}'
# Bypass marker
assert_silent no-destructive-git '{"tool_input":{"command":"# BYPASS_GIT_RM_FORCE_CHECK\ngit rm -f foo.py"}}'
# Cross-bypass: rm-force bypass must not silence chained reset --hard
assert_deny no-destructive-git '{"tool_input":{"command":"# BYPASS_GIT_RM_FORCE_CHECK\ngit rm -f foo; git reset --hard"}}' "reset --hard"
# Anchor-lib upgrade: ssh / sudo-flag wrappers + FP fixes
assert_deny no-destructive-git '{"tool_input":{"command":"ssh host git reset --hard HEAD~1"}}' "reset --hard"
assert_deny no-destructive-git '{"tool_input":{"command":"ssh user@host git clean -fd"}}' "git clean -f"
assert_deny no-destructive-git '{"tool_input":{"command":"sudo -n git rm -f foo.py"}}' "git rm -f"
assert_deny no-destructive-git '{"tool_input":{"command":"bash -c \"git checkout -- foo.py\""}}' "checkout --"
# FP fixes — string mentions are no longer flagged
assert_silent no-destructive-git '{"tool_input":{"command":"echo do not git reset --hard"}}'
assert_silent no-destructive-git '{"tool_input":{"command":"grep -r \"git rm -f\" ./docs"}}'

# no-dangerous-ops: every check has its own bypass marker.
#
# 1. Disk format / partition (mkfs, parted, fdisk, gdisk, sgdisk, cfdisk, wipefs;
#    cryptsetup luksFormat/erase/reencrypt). Allowed with --dry-run.
assert_deny no-dangerous-ops '{"tool_input":{"command":"mkfs.ext4 /dev/sdb1"}}' "disk-format"
assert_deny no-dangerous-ops '{"tool_input":{"command":"sudo mkfs -t ext4 /dev/sdc"}}' "disk-format"
assert_deny no-dangerous-ops '{"tool_input":{"command":"parted /dev/sda mklabel gpt"}}' "disk-format"
assert_deny no-dangerous-ops '{"tool_input":{"command":"sgdisk -Z /dev/sda"}}' "disk-format"
assert_deny no-dangerous-ops '{"tool_input":{"command":"wipefs -a /dev/sdb"}}' "disk-format"
assert_deny no-dangerous-ops '{"tool_input":{"command":"sudo cryptsetup luksFormat /dev/sda1"}}' "luksFormat"
# Anchor-lib upgrade: ssh / sudo-flag wrappers + FP fixes
assert_deny no-dangerous-ops '{"tool_input":{"command":"ssh host mkfs.ext4 /dev/sdb1"}}' "disk-format"
assert_deny no-dangerous-ops '{"tool_input":{"command":"sudo -u root mkfs.ext4 /dev/sdb1"}}' "disk-format"
assert_silent no-dangerous-ops '{"tool_input":{"command":"echo do not run mkfs.ext4 on prod"}}'
assert_silent no-dangerous-ops '{"tool_input":{"command":"grep -r parted ./docs"}}'
# --dry-run exempts
assert_silent no-dangerous-ops '{"tool_input":{"command":"parted --dry-run /dev/sda mklabel gpt"}}'
assert_silent no-dangerous-ops '{"tool_input":{"command":"mkfs.ext4 --dry-run /dev/sdb1"}}'
#
# 2. Block-device writes — target-based, any tool.
assert_deny no-dangerous-ops '{"tool_input":{"command":"dd if=image.iso of=/dev/sda bs=4M"}}' "/dev/<device>"
assert_deny no-dangerous-ops '{"tool_input":{"command":"dd of=/dev/nvme0n1 if=foo"}}' "/dev/<device>"
assert_deny no-dangerous-ops '{"tool_input":{"command":"dd of=/dev/sr0 if=cd.iso"}}' "/dev/<device>"
assert_deny no-dangerous-ops '{"tool_input":{"command":"dd of=/dev/mapper/cryptroot if=blob"}}' "/dev/<device>"
assert_deny no-dangerous-ops '{"tool_input":{"command":"dd of=/dev/loop0 if=blob"}}' "/dev/<device>"
assert_deny no-dangerous-ops '{"tool_input":{"command":"dd of=/dev/md0 if=blob"}}' "/dev/<device>"
assert_deny no-dangerous-ops '{"tool_input":{"command":"cp file.iso /dev/sda"}}' "/dev/<device>"
assert_deny no-dangerous-ops '{"tool_input":{"command":"cp file.iso /dev/sdb1"}}' "/dev/<device>"
assert_deny no-dangerous-ops '{"tool_input":{"command":"mv image /dev/sda"}}' "/dev/<device>"
assert_deny no-dangerous-ops '{"tool_input":{"command":"install -m 644 image /dev/sda"}}' "/dev/<device>"
assert_deny no-dangerous-ops '{"tool_input":{"command":"cat file.iso > /dev/sda"}}' "/dev/<device>"
assert_deny no-dangerous-ops '{"tool_input":{"command":"pv file.iso > /dev/sdb"}}' "/dev/<device>"
assert_deny no-dangerous-ops '{"tool_input":{"command":"echo hi >> /dev/sda"}}' "/dev/<device>"
assert_deny no-dangerous-ops '{"tool_input":{"command":"tee /dev/sda"}}' "/dev/<device>"
assert_deny no-dangerous-ops '{"tool_input":{"command":"tee -a /dev/nvme0n1"}}' "/dev/<device>"
# Path-traversal escape attempts must NOT slip through the safe-device allowlist
assert_deny no-dangerous-ops '{"tool_input":{"command":"cat foo > /dev/null/../sda"}}' "/dev/<device>"
assert_deny no-dangerous-ops '{"tool_input":{"command":"dd if=foo of=/dev/null/sub"}}' "/dev/<device>"
assert_deny no-dangerous-ops '{"tool_input":{"command":"echo > /dev/null2"}}' "/dev/<device>"
# Reads from /dev/<dev> are NOT writes — silent
assert_silent no-dangerous-ops '{"tool_input":{"command":"dd if=/dev/sda of=backup.img"}}'
assert_silent no-dangerous-ops '{"tool_input":{"command":"cp /dev/sda /tmp/backup.img"}}'
assert_silent no-dangerous-ops '{"tool_input":{"command":"hexdump -C /dev/sda"}}'
assert_silent no-dangerous-ops '{"tool_input":{"command":"lsblk /dev/sda"}}'
# Pseudo-device writes pass through the allowlist
assert_silent no-dangerous-ops '{"tool_input":{"command":"echo log > /dev/null"}}'
assert_silent no-dangerous-ops '{"tool_input":{"command":"dd if=foo of=/dev/null"}}'
assert_silent no-dangerous-ops '{"tool_input":{"command":"dd if=foo of=/dev/zero"}}'
assert_silent no-dangerous-ops '{"tool_input":{"command":"echo log > /dev/stderr"}}'
assert_silent no-dangerous-ops '{"tool_input":{"command":"echo hi > /dev/tty"}}'
assert_silent no-dangerous-ops '{"tool_input":{"command":"echo bytes > /dev/ttyUSB0"}}'
assert_silent no-dangerous-ops '{"tool_input":{"command":"echo bytes > /dev/ttyACM0"}}'
assert_silent no-dangerous-ops '{"tool_input":{"command":"echo > /dev/fd/3"}}'
assert_silent no-dangerous-ops '{"tool_input":{"command":"echo > /dev/pts/0"}}'
#
# 3. Privileged-config writes — /etc, /proc, /sys, /boot
assert_deny no-dangerous-ops '{"tool_input":{"command":"echo 1 > /proc/sys/kernel/sysrq"}}' "/etc, /proc, /sys"
assert_deny no-dangerous-ops '{"tool_input":{"command":"echo b > /proc/sysrq-trigger"}}' "/etc, /proc, /sys"
assert_deny no-dangerous-ops '{"tool_input":{"command":"sudo tee /etc/passwd"}}' "/etc, /proc, /sys"
assert_deny no-dangerous-ops '{"tool_input":{"command":"cp config /etc/myapp.conf"}}' "/etc, /proc, /sys"
assert_deny no-dangerous-ops '{"tool_input":{"command":"echo 0 > /sys/class/leds/foo/brightness"}}' "/etc, /proc, /sys"
assert_deny no-dangerous-ops '{"tool_input":{"command":"dd if=newkern of=/boot/vmlinuz"}}' "/etc, /proc, /sys"
# Reads of those paths are silent
assert_silent no-dangerous-ops '{"tool_input":{"command":"cat /etc/passwd"}}'
assert_silent no-dangerous-ops '{"tool_input":{"command":"cat /proc/cpuinfo"}}'
assert_silent no-dangerous-ops '{"tool_input":{"command":"cat /etc/passwd > /tmp/users"}}'
#
# 4. Secure-delete tools
assert_deny no-dangerous-ops '{"tool_input":{"command":"shred -u secret.txt"}}' "shred"
assert_deny no-dangerous-ops '{"tool_input":{"command":"srm -r /tmp/junk"}}' "shred"
assert_deny no-dangerous-ops '{"tool_input":{"command":"wipe -rf /tmp/junk"}}' "shred"
# Anchor-lib coverage: sudo + bash -c wrappers still trigger
assert_deny no-dangerous-ops '{"tool_input":{"command":"sudo srm -r /tmp/junk"}}' "shred"
assert_deny no-dangerous-ops '{"tool_input":{"command":"bash -c \"shred -u /tmp/x\""}}' "shred"
assert_deny no-dangerous-ops '{"tool_input":{"command":"xargs srm"}}' "shred"
# CMD_ANCHOR_SUDO with flags: `sudo -n`, `sudo -u root`, `sudo --non-interactive`
assert_deny no-dangerous-ops '{"tool_input":{"command":"sudo -n srm -r /tmp/junk"}}' "shred"
assert_deny no-dangerous-ops '{"tool_input":{"command":"sudo -u root srm -r /tmp/junk"}}' "shred"
assert_deny no-dangerous-ops '{"tool_input":{"command":"sudo --non-interactive srm /tmp/x"}}' "shred"
# CMD_WRAPPER_SSH coverage: `ssh [opts] host srm/shred/wipe`
assert_deny no-dangerous-ops '{"tool_input":{"command":"ssh host srm /tmp/x"}}' "shred"
assert_deny no-dangerous-ops '{"tool_input":{"command":"ssh user@host shred -u /etc/foo"}}' "shred"
assert_deny no-dangerous-ops '{"tool_input":{"command":"ssh -p 22 host wipe -rf /tmp/x"}}' "shred"
assert_deny no-dangerous-ops '{"tool_input":{"command":"ssh -i key.pem -o StrictHostKeyChecking=no host srm /x"}}' "shred"
# `wipefs` is the disk-format check, not secure-delete (already asserted above)
# Anchor-lib FP fixes — these previously tripped the bare \b match:
assert_silent no-dangerous-ops '{"tool_input":{"command":"echo do not srm /tmp/x"}}'
assert_silent no-dangerous-ops '{"tool_input":{"command":"ls /tmp/srm-cache"}}'
assert_silent no-dangerous-ops '{"tool_input":{"command":"# TODO: shred old logs later\nls"}}'
assert_silent no-dangerous-ops '{"tool_input":{"command":"grep -r wipe ./docs"}}'
# ssh-but-no-secure-delete is silent; ssh inside a string is not command position
assert_silent no-dangerous-ops '{"tool_input":{"command":"ssh host ls /tmp"}}'
assert_silent no-dangerous-ops '{"tool_input":{"command":"echo do not ssh into prod"}}'
#
# 5. Power-state operations
assert_deny no-dangerous-ops '{"tool_input":{"command":"sudo shutdown -h now"}}' "power state"
assert_deny no-dangerous-ops '{"tool_input":{"command":"reboot"}}' "power state"
assert_deny no-dangerous-ops '{"tool_input":{"command":"poweroff"}}' "power state"
assert_deny no-dangerous-ops '{"tool_input":{"command":"halt"}}' "power state"
assert_deny no-dangerous-ops '{"tool_input":{"command":"init 0"}}' "power state"
assert_deny no-dangerous-ops '{"tool_input":{"command":"init 6"}}' "power state"
assert_deny no-dangerous-ops '{"tool_input":{"command":"telinit 1"}}' "power state"
assert_deny no-dangerous-ops '{"tool_input":{"command":"systemctl poweroff"}}' "power state"
assert_deny no-dangerous-ops '{"tool_input":{"command":"systemctl reboot"}}' "power state"
assert_deny no-dangerous-ops '{"tool_input":{"command":"sudo kill -9 1"}}' "power state"
assert_deny no-dangerous-ops '{"tool_input":{"command":"kill -KILL 1"}}' "power state"
assert_deny no-dangerous-ops '{"tool_input":{"command":"kill -9 -1"}}' "power state"
# `git init` must not match power-state init regex (\binit\s+[016]\b requires digit)
assert_silent no-dangerous-ops '{"tool_input":{"command":"git init"}}'
assert_silent no-dangerous-ops '{"tool_input":{"command":"systemctl restart nginx"}}'
assert_silent no-dangerous-ops '{"tool_input":{"command":"kill 1234"}}'
# Anchor-lib upgrade: ssh / sudo-flag wrappers + FP fixes
assert_deny no-dangerous-ops '{"tool_input":{"command":"ssh host shutdown -h now"}}' "power state"
assert_deny no-dangerous-ops '{"tool_input":{"command":"sudo -n reboot"}}' "power state"
assert_silent no-dangerous-ops '{"tool_input":{"command":"echo about to reboot the cluster"}}'
assert_silent no-dangerous-ops '{"tool_input":{"command":"grep poweroff /var/log/messages"}}'
#
# 6. Recursive permission/ownership
assert_deny no-dangerous-ops '{"tool_input":{"command":"chmod -R 777 ./build"}}' "Recursive"
assert_deny no-dangerous-ops '{"tool_input":{"command":"chmod -Rfv 644 ./src"}}' "Recursive"
assert_deny no-dangerous-ops '{"tool_input":{"command":"chown -R root:root /opt/app"}}' "Recursive"
assert_silent no-dangerous-ops '{"tool_input":{"command":"chmod 755 ./script.sh"}}'
assert_silent no-dangerous-ops '{"tool_input":{"command":"chmod -h u+x foo"}}'
# Anchor-lib upgrade: ssh wrapper + FP fix
assert_deny no-dangerous-ops '{"tool_input":{"command":"ssh host chmod -R 777 /opt/app"}}' "Recursive"
assert_silent no-dangerous-ops '{"tool_input":{"command":"echo never run chmod -R on system paths"}}'
#
# 7. Docker prune
assert_deny no-dangerous-ops '{"tool_input":{"command":"docker system prune -af --volumes"}}' "docker"
assert_deny no-dangerous-ops '{"tool_input":{"command":"docker volume prune -f"}}' "docker"
assert_deny no-dangerous-ops '{"tool_input":{"command":"docker image prune -a"}}' "docker"
assert_silent no-dangerous-ops '{"tool_input":{"command":"docker ps"}}'
assert_silent no-dangerous-ops '{"tool_input":{"command":"docker rm specific-container"}}'
# Anchor-lib upgrade: ssh wrapper + FP fix
assert_deny no-dangerous-ops '{"tool_input":{"command":"ssh host docker volume prune -f"}}' "docker"
assert_silent no-dangerous-ops '{"tool_input":{"command":"echo do not run docker volume prune"}}'
#
# 8. Firewall wipe
assert_deny no-dangerous-ops '{"tool_input":{"command":"iptables -F"}}' "firewall"
assert_deny no-dangerous-ops '{"tool_input":{"command":"sudo iptables --flush"}}' "firewall"
assert_deny no-dangerous-ops '{"tool_input":{"command":"ip6tables -X"}}' "firewall"
assert_deny no-dangerous-ops '{"tool_input":{"command":"nft flush ruleset"}}' "firewall"
assert_deny no-dangerous-ops '{"tool_input":{"command":"sudo ufw reset"}}' "firewall"
assert_deny no-dangerous-ops '{"tool_input":{"command":"sudo ufw --force reset"}}' "firewall"
assert_silent no-dangerous-ops '{"tool_input":{"command":"iptables -L"}}'
assert_silent no-dangerous-ops '{"tool_input":{"command":"iptables -A INPUT -j ACCEPT"}}'
# Anchor-lib upgrade: ssh wrapper (locking yourself out of remote!) + FP fix
assert_deny no-dangerous-ops '{"tool_input":{"command":"ssh host iptables -F"}}' "firewall"
assert_silent no-dangerous-ops '{"tool_input":{"command":"echo iptables -F locks you out"}}'
#
# 9. crontab -r
assert_deny no-dangerous-ops '{"tool_input":{"command":"crontab -r"}}' "crontab"
assert_deny no-dangerous-ops '{"tool_input":{"command":"crontab -ri"}}' "crontab"
assert_deny no-dangerous-ops '{"tool_input":{"command":"crontab --remove"}}' "crontab"
assert_silent no-dangerous-ops '{"tool_input":{"command":"crontab -l"}}'
assert_silent no-dangerous-ops '{"tool_input":{"command":"crontab -e"}}'
# Anchor-lib upgrade: ssh wrapper + FP fix
assert_deny no-dangerous-ops '{"tool_input":{"command":"ssh host crontab -r"}}' "crontab"
assert_silent no-dangerous-ops '{"tool_input":{"command":"echo do not run crontab -r"}}'
#
# 10. killall
assert_deny no-dangerous-ops '{"tool_input":{"command":"killall firefox"}}' "killall"
assert_deny no-dangerous-ops '{"tool_input":{"command":"sudo killall -9 chrome"}}' "killall"
assert_silent no-dangerous-ops '{"tool_input":{"command":"pkill -f myapp"}}'
assert_silent no-dangerous-ops '{"tool_input":{"command":"pgrep firefox"}}'
# Anchor-lib upgrade: ssh wrapper + FP fix
assert_deny no-dangerous-ops '{"tool_input":{"command":"ssh host killall nginx"}}' "killall"
assert_silent no-dangerous-ops '{"tool_input":{"command":"echo do not killall in prod"}}'
assert_silent no-dangerous-ops '{"tool_input":{"command":"grep killall /var/log"}}'
#
# Unrelated commands
assert_silent no-dangerous-ops '{"tool_input":{"command":"ls /etc"}}'
#
# Bypass markers — each check is silenced by ITS OWN marker
assert_silent no-dangerous-ops '{"tool_input":{"command":"# BYPASS_DISK_FORMAT_CHECK\nmkfs.ext4 /dev/sdb1"}}'
assert_silent no-dangerous-ops '{"tool_input":{"command":"# BYPASS_DISK_FORMAT_CHECK\nsudo cryptsetup luksFormat /dev/sda1"}}'
assert_silent no-dangerous-ops '{"tool_input":{"command":"# BYPASS_BLOCKDEV_WRITE_CHECK\ndd if=foo of=/dev/sda"}}'
assert_silent no-dangerous-ops '{"tool_input":{"command":"# BYPASS_BLOCKDEV_WRITE_CHECK\ncp file.iso /dev/sda"}}'
assert_silent no-dangerous-ops '{"tool_input":{"command":"# BYPASS_BLOCKDEV_WRITE_CHECK\ncat foo > /dev/sda"}}'
assert_silent no-dangerous-ops '{"tool_input":{"command":"# BYPASS_SYSPATH_WRITE_CHECK\necho 1 > /proc/sys/kernel/sysrq"}}'
assert_silent no-dangerous-ops '{"tool_input":{"command":"# BYPASS_SYSPATH_WRITE_CHECK\nsudo tee /etc/passwd"}}'
assert_silent no-dangerous-ops '{"tool_input":{"command":"# BYPASS_SECURE_DELETE_CHECK\nshred -u secret.txt"}}'
assert_silent no-dangerous-ops '{"tool_input":{"command":"# BYPASS_POWER_STATE_CHECK\nshutdown -h now"}}'
assert_silent no-dangerous-ops '{"tool_input":{"command":"# BYPASS_POWER_STATE_CHECK\nkill -9 1"}}'
assert_silent no-dangerous-ops '{"tool_input":{"command":"# BYPASS_RECURSIVE_PERMS_CHECK\nchmod -R 777 ./build"}}'
assert_silent no-dangerous-ops '{"tool_input":{"command":"# BYPASS_DOCKER_PRUNE_CHECK\ndocker volume prune -f"}}'
assert_silent no-dangerous-ops '{"tool_input":{"command":"# BYPASS_FIREWALL_WIPE_CHECK\niptables -F"}}'
assert_silent no-dangerous-ops '{"tool_input":{"command":"# BYPASS_CRONTAB_REMOVE_CHECK\ncrontab -r"}}'
assert_silent no-dangerous-ops '{"tool_input":{"command":"# BYPASS_KILLALL_CHECK\nkillall firefox"}}'
# Cross-bypass: one bypass must NOT silence another check chained with it
assert_deny no-dangerous-ops '{"tool_input":{"command":"# BYPASS_DISK_FORMAT_CHECK\nmkfs.ext4 /dev/sdb1; killall firefox"}}' "killall"
assert_deny no-dangerous-ops '{"tool_input":{"command":"# BYPASS_BLOCKDEV_WRITE_CHECK\ndd of=/dev/sda; killall firefox"}}' "killall"
assert_deny no-dangerous-ops '{"tool_input":{"command":"# BYPASS_KILLALL_CHECK\nshutdown -h now; killall firefox"}}' "power state"

# no-git-amend: push --delete added alongside amend / force-push
assert_deny no-git-amend '{"tool_input":{"command":"git push --delete origin feature"}}' "push --delete"
assert_deny no-git-amend '{"tool_input":{"command":"git push -d origin feature"}}' "push --delete"
assert_deny no-git-amend '{"tool_input":{"command":"git push origin :feature"}}' "push --delete"
assert_deny no-git-amend '{"tool_input":{"command":"git push origin :refs/heads/feature"}}' "push --delete"
assert_silent no-git-amend '{"tool_input":{"command":"git push origin feature"}}'
assert_silent no-git-amend '{"tool_input":{"command":"git push origin main:main"}}'
assert_silent no-git-amend '{"tool_input":{"command":"# BYPASS_PUSH_DELETE_CHECK\ngit push --delete origin feature"}}'
# Force-push bypass must NOT silence chained --delete
assert_deny no-git-amend '{"tool_input":{"command":"# BYPASS_FORCE_PUSH_CHECK\ngit push --force; git push --delete origin x"}}' "push --delete"
# Anchor-lib upgrade: ssh / sudo-flag wrappers + FP fixes
assert_deny no-git-amend '{"tool_input":{"command":"ssh host git commit --amend"}}' "git commit --amend"
assert_deny no-git-amend '{"tool_input":{"command":"ssh host git push --force"}}' "push --force"
assert_deny no-git-amend '{"tool_input":{"command":"sudo -n git push --delete origin feature"}}' "push --delete"
assert_deny no-git-amend '{"tool_input":{"command":"bash -c \"git commit --amend\""}}' "git commit --amend"
# FP fixes — string mentions are no longer flagged
assert_silent no-git-amend '{"tool_input":{"command":"echo do not git push --force"}}'
assert_silent no-git-amend '{"tool_input":{"command":"grep -r \"git commit --amend\" ./docs"}}'

assert_deny no-pip-npm "$(jq -n --arg c "pip install foo" '{tool_input:{command:$c}}')" "Use uv instead"
assert_deny no-pip-npm "$(jq -n --arg c "npm install" '{tool_input:{command:$c}}')" "Use pnpm"
assert_silent no-pip-npm '{"tool_input":{"command":"uv add foo"}}'
# Shared anchor lib: sudo + wrapper coverage for pip/npm
assert_deny no-pip-npm '{"tool_input":{"command":"sudo pip install foo"}}' "Use uv instead"
assert_deny no-pip-npm '{"tool_input":{"command":"sudo npm install"}}' "Use pnpm"
assert_deny no-pip-npm '{"tool_input":{"command":"bash -c \"pip install foo\""}}' "Use uv instead"
assert_deny no-pip-npm '{"tool_input":{"command":"sudo bash -c \"npm install\""}}' "Use pnpm"
# Substring guards: pipenv / pip-tools / pnpm must NOT trigger
assert_silent no-pip-npm '{"tool_input":{"command":"pipenv install foo"}}'
assert_silent no-pip-npm '{"tool_input":{"command":"pip-tools compile"}}'
assert_silent no-pip-npm '{"tool_input":{"command":"pnpm install"}}'
assert_silent no-pip-npm '{"tool_input":{"command":"sudo pnpm install"}}'

assert_deny no-worktree-team '{"tool_input":{"isolation":"worktree","team_name":"foo"}}' "worktree silently fails"
assert_silent no-worktree-team '{"tool_input":{"isolation":"worktree"}}'

assert_deny no-cat-write "$(jq -n --arg c "cat << EOF ${REDIR} /tmp/x
hi
EOF" '{tool_input:{command:$c}}')" "Write tool"
assert_silent no-cat-write '{"tool_input":{"command":"cat /tmp/x"}}'
# Shared anchor lib: wrapper coverage for cat heredoc-write
assert_deny no-cat-write "$(jq -n --arg c "bash -c \"cat << EOF ${REDIR} /tmp/x
hi
EOF\"" '{tool_input:{command:$c}}')" "Write tool"
# sudo coverage: Write runs without elevated privileges, so any
# `sudo cat << EOF > <target>` (regardless of where <target> lives) has no
# Write-tool substitute → silent.
assert_silent no-cat-write "$(jq -n --arg c "sudo cat << EOF ${REDIR} /etc/myapp.conf
hi
EOF" '{tool_input:{command:$c}}')"
assert_silent no-cat-write "$(jq -n --arg c "sudo bash -c \"cat << EOF ${REDIR} /etc/x
hi
EOF\"" '{tool_input:{command:$c}}')"
assert_silent no-cat-write "$(jq -n --arg c "bash -c \"sudo cat << EOF ${REDIR} /etc/x
hi
EOF\"" '{tool_input:{command:$c}}')"
# A stray sudo earlier in a chained command must NOT silence the cat-write check
assert_deny no-cat-write "$(jq -n --arg c "sudo apt update; cat << EOF ${REDIR} /tmp/x
hi
EOF" '{tool_input:{command:$c}}')" "Write tool"

assert_deny no-sed-print "$(jq -n --arg c "sed -n '12,13p' /tmp/x" '{tool_input:{command:$c}}')" "sed -n"
assert_silent no-sed-print '{"tool_input":{"command":"sed s/a/b/g /tmp/x"}}'
# sudo coverage: Read runs without elevated privileges, so any
# `sudo sed -n '12p' <target>` (regardless of where <target> lives) has no
# Read-tool substitute → silent.
assert_silent no-sed-print "$(jq -n --arg c "sudo sed -n '12,13p' /etc/shadow" '{tool_input:{command:$c}}')"
# A stray sudo earlier in a chained command must NOT silence the sed-print check
assert_deny no-sed-print "$(jq -n --arg c "sudo apt update; sed -n '12,13p' /tmp/x" '{tool_input:{command:$c}}')" "sed -n"

assert_deny python-unbuffered '{"tool_input":{"command":"python3 script.py","run_in_background":true},"cwd":"/tmp"}' "unbuffered output"
assert_silent python-unbuffered '{"tool_input":{"command":"python3 script.py"}}'

assert_deny no-head-read '{"tool_input":{"command":"head -n 80 /tmp/x"}}' "Read tool"
assert_silent no-head-read '{"tool_input":{"command":"head -c 100 /tmp/x"}}'
# Command-position regex: piped-into-cmd is also command-position
assert_deny no-head-read '{"tool_input":{"command":"echo x | head -n 80 /tmp/x"}}' "Read tool"
# sudo coverage: Read runs without elevated privileges, so any
# `sudo head -N <target>` (regardless of where <target> lives) has no
# Read-tool substitute → silent.
assert_silent no-head-read '{"tool_input":{"command":"sudo head -n 80 /etc/shadow"}}'
# A stray sudo earlier in a chained command must NOT silence the head-read check
assert_deny no-head-read '{"tool_input":{"command":"sudo apt update; head -n 80 /tmp/x"}}' "Read tool"

# no-head-tail-pipe: trailing `| head` / `| tail` truncates internal output
assert_deny no-head-tail-pipe '{"tool_input":{"command":"ls | head"}}' "truncate by line position"
assert_deny no-head-tail-pipe '{"tool_input":{"command":"cat /tmp/x | tail -n 5"}}' "truncate by line position"
assert_deny no-head-tail-pipe '{"tool_input":{"command":"git log | head -20"}}' "BYPASS_HEAD_TAIL_CHECK"
assert_deny no-head-tail-pipe '{"tool_input":{"command":"ls | head"}}' "If legitimate or false-positive"
assert_silent no-head-tail-pipe '{"tool_input":{"command":"ls"}}'
# Bare `head -n N <file>` lacks a leading pipe — separate hook (no-head-read) handles it
assert_silent no-head-tail-pipe '{"tool_input":{"command":"head -n 5 /tmp/x"}}'
# Intermediate head — output still continues into another pipe stage, not truncating
assert_silent no-head-tail-pipe '{"tool_input":{"command":"cmd | head | wc -l"}}'
# `||` is logical-or, not a pipe
assert_silent no-head-tail-pipe '{"tool_input":{"command":"cmd || head -n 5 file"}}'
assert_silent no-head-tail-pipe '{"tool_input":{"command":"# BYPASS_HEAD_TAIL_CHECK\nls | head"}}'
assert_deny no-sed-print "$(jq -n --arg c "echo x | sed -n '12,13p' /tmp/x" '{tool_input:{command:$c}}')" "sed -n"
assert_deny no-cat-write "$(jq -n --arg c "echo go | cat << EOF ${REDIR} /tmp/x
hi
EOF" '{tool_input:{command:$c}}')" "Write tool"

# Build a long heredoc payload (>80 lines) — encode via jq to keep JSON valid
long_payload=$(for i in $(seq 1 90); do echo "line $i"; done)
heredoc_cmd="python3 <<EOF
${long_payload}
EOF"
assert_deny no-heredoc "$(jq -n --arg c "$heredoc_cmd" '{tool_input:{command:$c}}')" "lines detected"
assert_silent no-heredoc '{"tool_input":{"command":"echo hi"}}'
# Heredoc trigger suggests BYPASS_HEREDOC_RESTRICTION in the error
assert_deny no-heredoc "$(jq -n --arg c "$heredoc_cmd" '{tool_input:{command:$c}}')" "BYPASS_HEREDOC_RESTRICTION"
# Bypass marker silences the hook even on a >80-line heredoc
heredoc_bypass="# BYPASS_HEREDOC_RESTRICTION
${heredoc_cmd}"
assert_silent no-heredoc "$(jq -n --arg c "$heredoc_bypass" '{tool_input:{command:$c}}')"
# Every hook's bypass marker silences its own trigger
assert_silent no-devnull-redirect "$(jq -n --arg c "# BYPASS_DEVNULL_CHECK
ls ${REDIR}${DEV}" '{tool_input:{command:$c}}')"
assert_silent no-background-ampersand "$(jq -n --arg c "# BYPASS_BACKGROUND_CHECK
sleep 10 ${AMP}" '{tool_input:{command:$c}}')"
assert_silent no-cat-write "$(jq -n --arg c "# BYPASS_CAT_WRITE
cat << EOF ${REDIR} /tmp/x
hi
EOF" '{tool_input:{command:$c}}')"
assert_silent no-head-read '{"tool_input":{"command":"# BYPASS_HEAD_READ_CHECK\nhead -n 80 /tmp/x"}}'
assert_silent no-sed-print "$(jq -n --arg c "# BYPASS_SED_PRINT_CHECK
sed -n '12,13p' /tmp/x" '{tool_input:{command:$c}}')"
assert_silent no-pip-npm '{"tool_input":{"command":"# BYPASS_PACKAGE_MANAGER_CHECK\npip install foo"}}'
assert_silent no-pip-npm '{"tool_input":{"command":"# BYPASS_PACKAGE_MANAGER_CHECK\nnpm install"}}'
assert_silent no-git-amend '{"tool_input":{"command":"# BYPASS_AMEND_CHECK\ngit commit --amend"}}'
assert_silent no-git-amend '{"tool_input":{"command":"# BYPASS_FORCE_PUSH_CHECK\ngit push --force"}}'
# G1 regression: amend bypass must not silence chained force-push
assert_deny no-git-amend '{"tool_input":{"command":"# BYPASS_AMEND_CHECK\ngit commit --amend; git push --force"}}' "push --force"
assert_deny no-git-amend '{"tool_input":{"command":"# BYPASS_FORCE_PUSH_CHECK\ngit commit --amend; git push --force"}}' "git commit --amend"
assert_silent python-unbuffered '{"tool_input":{"command":"# BYPASS_UNBUFFERED_CHECK\npython3 script.py","run_in_background":true},"cwd":"/tmp"}'
# Empty command should be silent (no-background-ampersand previously had no guard)
assert_silent no-background-ampersand '{"tool_input":{"command":""}}'
# Unified hint wording — every bypass hint emitted by emit_pre_tool_deny_bypassable
# now opens with "If legitimate or false-positive, prepend `# BYPASS_X` to the Bash
# command." The two-branch wording lets the agent know the bypass marker also covers
# regex misfires (e.g. pattern matched inside a quoted string), not only "I really
# mean to do this" cases.
assert_deny no-devnull-redirect "$(jq -n --arg c "ls ${REDIR}${DEV}" '{tool_input:{command:$c}}')" "If legitimate or false-positive"
assert_deny no-background-ampersand "$(jq -n --arg c "sleep 10 ${AMP}" '{tool_input:{command:$c}}')" "If legitimate or false-positive"
assert_deny no-cat-write "$(jq -n --arg c "cat << EOF ${REDIR} /tmp/x
hi
EOF" '{tool_input:{command:$c}}')" "If legitimate or false-positive"
assert_deny no-heredoc "$(jq -n --arg c "$heredoc_cmd" '{tool_input:{command:$c}}')" "If legitimate or false-positive"
# FP-aware branch must be in the message too
assert_deny no-devnull-redirect "$(jq -n --arg c "ls ${REDIR}${DEV}" '{tool_input:{command:$c}}')" "false-positive"

# no-schedule-wakeup-deadzone: delays in [300,1800] denied (inclusive boundaries)
assert_deny no-schedule-wakeup-deadzone '{"tool_input":{"delaySeconds":600,"reason":"x"}}' "dead zone"
assert_deny no-schedule-wakeup-deadzone '{"tool_input":{"delaySeconds":300,"reason":"x"}}' "dead zone"
assert_deny no-schedule-wakeup-deadzone '{"tool_input":{"delaySeconds":1800,"reason":"x"}}' "dead zone"
assert_silent no-schedule-wakeup-deadzone '{"tool_input":{"delaySeconds":120,"reason":"x"}}'
assert_silent no-schedule-wakeup-deadzone '{"tool_input":{"delaySeconds":299,"reason":"x"}}'
assert_silent no-schedule-wakeup-deadzone '{"tool_input":{"delaySeconds":1801,"reason":"x"}}'
assert_silent no-schedule-wakeup-deadzone '{"tool_input":{"delaySeconds":2000,"reason":"x"}}'
# Bypass marker in reason silences the deny
assert_silent no-schedule-wakeup-deadzone '{"tool_input":{"delaySeconds":600,"reason":"BYPASS_WAKEUP_DEADZONE — needed"}}'
# Non-numeric delaySeconds coerces to 0 → silent (guards against schema drift)
assert_silent no-schedule-wakeup-deadzone '{"tool_input":{"delaySeconds":"abc","reason":"x"}}'
# String-encoded number still evaluates numerically
assert_deny no-schedule-wakeup-deadzone '{"tool_input":{"delaySeconds":"600","reason":"x"}}' "dead zone"

echo ""
echo "=== PreToolUse defaulting hooks ==="

# explore-model-sonnet: only inject model="sonnet" when the calling main agent
# is itself running on opus. Sonnet/Haiku parents (and undeterminable sessions)
# pass through untouched.
em_dir=$(mktemp -d)
em_opus="$em_dir/opus.jsonl"
em_haiku="$em_dir/haiku.jsonl"
em_synth="$em_dir/synth.jsonl"
em_unread="$em_dir/missing.jsonl"
printf '%s\n' '{"type":"assistant","message":{"model":"claude-opus-4-7"}}' > "$em_opus"
printf '%s\n' '{"type":"assistant","message":{"model":"claude-haiku-4-5-20251001"}}' > "$em_haiku"
# synthetic-only transcript: no real model recorded yet → should fall back to silent
printf '%s\n' '{"type":"assistant","message":{"model":"<synthetic>"}}' > "$em_synth"

# 1. Opus parent + no model → inject sonnet
out=$(printf '%s' "$(jq -nc --arg t "$em_opus" '{transcript_path:$t,tool_input:{subagent_type:"Explore",prompt:"x"}}')" | bash ~/.claude/hooks/explore-model-sonnet.sh)
echo "$out" | jq -e '.hookSpecificOutput.permissionDecision == "allow" and .hookSpecificOutput.updatedInput.model == "sonnet"' > "$test_out" \
  && echo "OK:   explore-model-sonnet injects sonnet for opus parent" \
  || { echo "FAIL: explore-model-sonnet opus-parent inject: $out"; fail=1; }

# 2. Haiku parent + no model → silent (don't downgrade haiku→sonnet)
out=$(printf '%s' "$(jq -nc --arg t "$em_haiku" '{transcript_path:$t,tool_input:{subagent_type:"Explore",prompt:"x"}}')" | bash ~/.claude/hooks/explore-model-sonnet.sh)
[ -z "$out" ] \
  && echo "OK:   explore-model-sonnet silent for haiku parent" \
  || { echo "FAIL: explore-model-sonnet should be silent for haiku parent: $out"; fail=1; }

# 3. Opus parent + explicit model already set → silent (don't override caller)
out=$(printf '%s' "$(jq -nc --arg t "$em_opus" '{transcript_path:$t,tool_input:{subagent_type:"Explore",prompt:"x",model:"haiku"}}')" | bash ~/.claude/hooks/explore-model-sonnet.sh)
[ -z "$out" ] \
  && echo "OK:   explore-model-sonnet silent when caller set model" \
  || { echo "FAIL: explore-model-sonnet should respect caller model: $out"; fail=1; }

# 4. Non-Explore subagent → silent regardless of parent model
out=$(printf '%s' "$(jq -nc --arg t "$em_opus" '{transcript_path:$t,tool_input:{subagent_type:"Plan",prompt:"x"}}')" | bash ~/.claude/hooks/explore-model-sonnet.sh)
[ -z "$out" ] \
  && echo "OK:   explore-model-sonnet silent for non-Explore subagent" \
  || { echo "FAIL: explore-model-sonnet should be silent for non-Explore: $out"; fail=1; }

# 5. Missing transcript_path → silent (can't determine parent model, fail closed)
out=$(printf '%s' '{"tool_input":{"subagent_type":"Explore","prompt":"x"}}' | bash ~/.claude/hooks/explore-model-sonnet.sh)
[ -z "$out" ] \
  && echo "OK:   explore-model-sonnet silent without transcript_path" \
  || { echo "FAIL: explore-model-sonnet should be silent without transcript: $out"; fail=1; }

# 6. Unreadable transcript_path → silent
out=$(printf '%s' "$(jq -nc --arg t "$em_unread" '{transcript_path:$t,tool_input:{subagent_type:"Explore",prompt:"x"}}')" | bash ~/.claude/hooks/explore-model-sonnet.sh)
[ -z "$out" ] \
  && echo "OK:   explore-model-sonnet silent on unreadable transcript" \
  || { echo "FAIL: explore-model-sonnet should be silent on unreadable transcript: $out"; fail=1; }

# 7. Synthetic-only transcript (no real assistant model yet) → silent
out=$(printf '%s' "$(jq -nc --arg t "$em_synth" '{transcript_path:$t,tool_input:{subagent_type:"Explore",prompt:"x"}}')" | bash ~/.claude/hooks/explore-model-sonnet.sh)
[ -z "$out" ] \
  && echo "OK:   explore-model-sonnet silent on synthetic-only transcript" \
  || { echo "FAIL: explore-model-sonnet should be silent on synthetic-only: $out"; fail=1; }

rm -rf "$em_dir"

echo ""
echo "=== PostToolUse regression ==="

out=$(printf '%s' '{"tool_response":{"results":[{"url":"https://x","title":"X"}]}}' | bash ~/.claude/hooks/websearch-followup-hint.sh)
echo "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("WebFetch")' > "$test_out" && echo "OK:   websearch (with results) fires" || { echo "FAIL: websearch with results"; fail=1; }

out=$(printf '%s' '{"tool_response":{"results":[]}}' | bash ~/.claude/hooks/websearch-followup-hint.sh)
[ -z "$out" ] && echo "OK:   websearch (0 results) silent" || { echo "FAIL: websearch 0 results: $out"; fail=1; }

assert_context reread-after-edit '{"tool_input":{"file_path":"/tmp/x"}}' "/tmp/x"
assert_silent reread-after-edit '{"tool_input":{}}'

assert_context verify-explore-results '{"tool_input":{"subagent_type":"Explore"}}' "Verify Explore"
assert_silent verify-explore-results '{"tool_input":{"subagent_type":"Plan"}}'

echo ""
echo "=== PostToolUse: hooks using emit helper ==="

# cache-keepalive-hint: fires on backgrounded Bash and Agent; silent on foreground
assert_context cache-keepalive-hint '{"tool_name":"Bash","tool_input":{"run_in_background":true,"command":"sleep 60"}}' "Background Bash"
assert_context cache-keepalive-hint '{"tool_name":"Agent","tool_input":{"run_in_background":true}}' "Background agent"
assert_silent cache-keepalive-hint '{"tool_name":"Bash","tool_input":{"command":"ls"},"tool_response":{}}'

# prefer-uv-run: fires on bare python3; silent when uv run is already used
assert_context prefer-uv-run '{"tool_input":{"command":"python3 foo.py"}}' "uv run python"
assert_silent prefer-uv-run '{"tool_input":{"command":"uv run python foo.py"}}'

# python-unbuffered-post: fires on auto-backgrounded python; silent on no bg
assert_context python-unbuffered-post '{"tool_input":{"command":"python3 long.py","run_in_background":false},"tool_response":{"backgroundTaskId":"bg-1"},"cwd":"/tmp"}' "PYTHONUNBUFFERED"
assert_silent python-unbuffered-post '{"tool_input":{"command":"ls"},"tool_response":{}}'

# pep723-script: fires on wrong shebang and on missing PEP 723 block; silent on non-.py
pep723_wrong=$(jq -n --arg c "#!/usr/bin/python3
print(1)" '{tool_input:{file_path:"/tmp/x.py",content:$c}}')
assert_context pep723-script "$pep723_wrong" "Fix shebang"

pep723_missing=$(jq -n --arg c "#!/usr/bin/env -S uv run --script
print(1)" '{tool_input:{file_path:"/tmp/x.py",content:$c}}')
assert_context pep723-script "$pep723_missing" "PEP 723"

assert_silent pep723-script '{"tool_input":{"file_path":"/tmp/x.txt","content":"hello"}}'

echo ""
echo "=== UserPromptSubmit hooks ==="

# inject-time: always emits a "Message time: ..." additionalContext.
out=$(bash ~/.claude/hooks/inject-time.sh)
echo "$out" | jq -e '.hookSpecificOutput.additionalContext | startswith("Message time:")' > "$test_out" \
  && echo "OK:   inject-time fires" \
  || { echo "FAIL: inject-time: $out"; fail=1; }

# inject-git-status: emits "Git status:" context inside a repo, silent outside,
# and silent on a repeat fire when status hasn't changed (cached at
# /tmp/claude-git-status/<SID>). Hook depends on cwd, so pin both explicitly.
sid="test-$$"
rm -f "/tmp/claude-git-status/$sid"
gs_in="{\"session_id\":\"$sid\"}"

out=$(cd ~/.claude && printf '%s' "$gs_in" | bash ~/.claude/hooks/inject-git-status.sh)
echo "$out" | jq -e '.hookSpecificOutput.additionalContext | startswith("Git status")' > "$test_out" \
  && echo "OK:   inject-git-status fires inside repo (first time)" \
  || { echo "FAIL: inject-git-status first fire: $out"; fail=1; }

# Second fire with same status → cache hit → silent
out=$(cd ~/.claude && printf '%s' "$gs_in" | bash ~/.claude/hooks/inject-git-status.sh)
[ -z "$out" ] \
  && echo "OK:   inject-git-status silent on unchanged status" \
  || { echo "FAIL: inject-git-status repeat fire: $out"; fail=1; }

out=$(cd /tmp && printf '%s' "$gs_in" | bash ~/.claude/hooks/inject-git-status.sh)
[ -z "$out" ] \
  && echo "OK:   inject-git-status silent outside repo" \
  || { echo "FAIL: inject-git-status outside repo: $out"; fail=1; }

rm -f "/tmp/claude-git-status/$sid"

# inject-system-load: silent when thresholds pinned impossibly high,
# fires when a single path is forced low (DISK below — see trip block
# for why DISK is the deterministic forcing signal). Other paths in
# each assertion are pinned to the opposite extreme so a real elevated
# metric on the test box can't leak across assertions.
SILENT_ENV=(
  SYSLOAD_CPU_FACTOR=999
  SYSLOAD_MEM_PCT=101
  SYSLOAD_SWAP_PCT=101
  SYSLOAD_DISK_PCT=101
  SYSLOAD_GPU_UTIL=101
  SYSLOAD_GPU_MEM=101
)
TRIP_ENV=(
  SYSLOAD_CPU_FACTOR=999
  SYSLOAD_MEM_PCT=101
  SYSLOAD_SWAP_PCT=101
  SYSLOAD_DISK_PCT=0
  SYSLOAD_GPU_UTIL=101
  SYSLOAD_GPU_MEM=101
)

# Use a unique per-run session_id so the cooldown cache starts clean and
# can't bleed across harness invocations.
sysl_sid="syslt-$$"
sysl_in="{\"session_id\":\"$sysl_sid\"}"
sysl_cache="/tmp/claude-system-load/$sysl_sid"
rm -f "$sysl_cache"

out=$(env "${SILENT_ENV[@]}" bash ~/.claude/hooks/inject-system-load.sh <<< "$sysl_in")
[ -z "$out" ] \
  && echo "OK:   inject-system-load silent when no threshold tripped" \
  || { echo "FAIL: inject-system-load should be silent: $out"; fail=1; }

# Force DISK trip: %used from `df -P /` is always >0 on a mounted root
# (filesystem metadata + journal alone exceed 1%), so DISK_PCT=0 reliably
# trips. Avoid the MEM/SWAP paths for forcing — both compute %used via
# integer division, which floors to 0 on a high-RAM box (≥200 GB) when
# absolute usage is <1% of total, making those tests non-deterministic on
# lightly-loaded CI runners.
out=$(env "${TRIP_ENV[@]}" bash ~/.claude/hooks/inject-system-load.sh <<< "$sysl_in")
echo "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("DISK")' > "$test_out" \
  && echo "OK:   inject-system-load fires on DISK trip (first fire)" \
  || { echo "FAIL: inject-system-load DISK trip: $out"; fail=1; }

# Cooldown: same elevated state on a repeat fire matches the cached
# bucketed signature → silent, even though DISK is still tripping.
out=$(env "${TRIP_ENV[@]}" bash ~/.claude/hooks/inject-system-load.sh <<< "$sysl_in")
[ -z "$out" ] \
  && echo "OK:   inject-system-load silent on repeat (cooldown cache hit)" \
  || { echo "FAIL: inject-system-load should be silent on repeat: $out"; fail=1; }

# Returning to clean state writes empty signature; no emit, but cache
# now invalidates so a subsequent re-trip would emit again.
out=$(env "${SILENT_ENV[@]}" bash ~/.claude/hooks/inject-system-load.sh <<< "$sysl_in")
[ -z "$out" ] \
  && echo "OK:   inject-system-load silent on elevated→clean transition" \
  || { echo "FAIL: inject-system-load clean-after-trip: $out"; fail=1; }

# Re-trip after going clean: cache mismatch → emits again.
out=$(env "${TRIP_ENV[@]}" bash ~/.claude/hooks/inject-system-load.sh <<< "$sysl_in")
echo "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("DISK")' > "$test_out" \
  && echo "OK:   inject-system-load fires again after returning to elevated" \
  || { echo "FAIL: inject-system-load re-trip: $out"; fail=1; }

rm -f "$sysl_cache"

# inject-peer-activity: surfaces busy peer Claude sessions sharing the repo.
# Override hooks (PEER_ACTIVITY_TEST_*) bypass the live tmux/git lookups so the
# filter logic is tested deterministically without spawning a tmux server.

# 1. No tmux: TMUX_PANE unset → silent (real-world: user runs Claude outside tmux)
out=$(env -u TMUX_PANE bash ~/.claude/hooks/inject-peer-activity.sh </dev/null)
[ -z "$out" ] \
  && echo "OK:   inject-peer-activity silent without tmux" \
  || { echo "FAIL: inject-peer-activity should be silent without tmux: $out"; fail=1; }

# 2. Idle peer in same repo → silent (no collision risk)
peers_idle=$'claude\t_claude:5.1\t/home/ubuntu/.claude\t✳ idle-task'
out=$(PEER_ACTIVITY_TEST_SELF_ADDR=_claude:6.1 \
      PEER_ACTIVITY_TEST_SELF_ROOT=/home/ubuntu/.claude \
      PEER_ACTIVITY_TEST_PANES="$peers_idle" \
      bash ~/.claude/hooks/inject-peer-activity.sh </dev/null)
[ -z "$out" ] \
  && echo "OK:   inject-peer-activity silent on idle-only peer" \
  || { echo "FAIL: inject-peer-activity should be silent on idle peer: $out"; fail=1; }

# 3. Busy peer in same repo → emits context citing peer addr + task
peers_busy=$'claude\t_claude:6.1\t/home/ubuntu/.claude\t⠂ peer-activity-awareness-hook
claude\t_claude:6.2\t/home/ubuntu/.claude\t⠐ sysload-test-disk-forcing
claude\t_claude:7.1\t/home/ubuntu/.claude/skills\t⠂ subdir-task
claude\t_claude:5.1\t/home/ubuntu/.claude\t✳ idle-task
fish\trql2:1.1\t/home/ubuntu/.claude\t~/rql2 - fish
claude\trql2:3.1\t/home/ubuntu/rql2\t⠂ unrelated-busy'
out=$(PEER_ACTIVITY_TEST_SELF_ADDR=_claude:6.1 \
      PEER_ACTIVITY_TEST_SELF_ROOT=/home/ubuntu/.claude \
      PEER_ACTIVITY_TEST_PANES="$peers_busy" \
      bash ~/.claude/hooks/inject-peer-activity.sh </dev/null)
echo "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("_claude:6.2") and contains("sysload-test-disk-forcing") and contains("_claude:7.1") and contains("subdir-task")' > "$test_out" \
  && echo "OK:   inject-peer-activity fires on busy peers in repo" \
  || { echo "FAIL: inject-peer-activity busy peers: $out"; fail=1; }
# Cross-check exclusions: self, idle, non-claude pane, unrelated repo all absent
echo "$out" | jq -e '.hookSpecificOutput.additionalContext
    | (contains("_claude:6.1") or contains("_claude:5.1") or contains("rql2:1.1") or contains("rql2:3.1")) | not' > "$test_out" \
  && echo "OK:   inject-peer-activity excludes self/idle/non-claude/other-repo" \
  || { echo "FAIL: inject-peer-activity exclusion: $out"; fail=1; }

rm -f "$test_out"

echo ""
if [ $fail -eq 0 ]; then
  echo "ALL TESTS PASS"
else
  echo "$fail failures"
fi
exit $fail
