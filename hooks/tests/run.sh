#!/usr/bin/bash
# Test harness for migrated hooks. Deliberately contains trigger patterns;
# hooks see only the outer `bash /tmp/hook-test.sh` invocation.

# Scrub env that some hooks consult, so tests reproduce the hook behavior a
# fresh user environment would see (Claude's runtime env can set
# PYTHONUNBUFFERED, masking deny tests).
unset PYTHONUNBUFFERED
unset ANTHROPIC_BASE_URL
unset ANTHROPIC_DEFAULT_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL
unset ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_OPUS_MODEL

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

assert_silent_env() {
  local name="$1" input="$2" env_name="$3" env_value="$4"
  local out
  out=$(printf '%s' "$input" | env "$env_name=$env_value" bash ~/.claude/hooks/$name.sh 2>&1)
  if [ -n "$out" ]; then
    echo "FAIL: $name should be silent with $env_name=$env_value"
    echo "  got: $out"
    fail=1
  else
    echo "OK:   $name silent ($env_name=$env_value)"
  fi
}

assert_deny_env() {
  local name="$1" input="$2" pattern="$3" env_name="$4" env_value="$5"
  local out
  out=$(printf '%s' "$input" | env "$env_name=$env_value" bash ~/.claude/hooks/$name.sh 2>&1)
  if [ -z "$out" ] || ! echo "$out" | jq -e ".hookSpecificOutput.permissionDecision == \"deny\" and (.hookSpecificOutput.permissionDecisionReason | contains(\"$pattern\"))" > "$test_out"; then
    echo "FAIL: $name should deny with pattern '$pattern' with $env_name=$env_value"
    echo "  got: $out"
    fail=1
  else
    echo "OK:   $name deny ($pattern, $env_name=$env_value)"
  fi
}

assert_context_env() {
  local name="$1" input="$2" pattern="$3" env_name="$4" env_value="$5"
  local out
  out=$(printf '%s' "$input" | env "$env_name=$env_value" bash ~/.claude/hooks/$name.sh 2>&1)
  if ! echo "$out" | jq -e ".hookSpecificOutput.additionalContext | contains(\"$pattern\")" > "$test_out"; then
    echo "FAIL: $name should emit additionalContext containing '$pattern' with $env_name=$env_value"
    echo "  got: $out"
    fail=1
  else
    echo "OK:   $name context ($pattern, $env_name=$env_value)"
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
# fastpath regression: tool-name-only invocations (no /dev/ path) must still deny
assert_deny no-dangerous-ops '{"tool_input":{"command":"sgdisk -Z disk.img"}}' "disk-format"
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

# no-head-tail-pipe: soft oneshot hint — trailing `| head` / `| tail`
# truncates the internal pipeline output. First trigger per session emits
# additionalContext; subsequent triggers in the same session are silent.
nht_sid="nht-$$"
nht_cache_dir=/tmp/claude-hint-no-head-tail-pipe
nht_cache="$nht_cache_dir/$nht_sid"
rm -f "$nht_cache"

# 1. First fire on `ls | head` → hint emitted (no permissionDecision)
out=$(printf '%s' "$(jq -nc --arg s "$nht_sid" '{session_id:$s,tool_input:{command:"ls | head"}}')" \
       | bash ~/.claude/hooks/no-head-tail-pipe.sh)
echo "$out" | jq -e '(.hookSpecificOutput.permissionDecision | not) and (.hookSpecificOutput.additionalContext | contains("truncates by line position"))' > "$test_out" \
  && echo "OK:   no-head-tail-pipe emits hint on first trailing-head pipe" \
  || { echo "FAIL: no-head-tail-pipe first fire: $out"; fail=1; }

# 2. Second trigger same session → cache hit, silent
out=$(printf '%s' "$(jq -nc --arg s "$nht_sid" '{session_id:$s,tool_input:{command:"cat /tmp/x | tail -n 5"}}')" \
       | bash ~/.claude/hooks/no-head-tail-pipe.sh)
[ -z "$out" ] \
  && echo "OK:   no-head-tail-pipe silent on repeat in same session" \
  || { echo "FAIL: no-head-tail-pipe should be silent on repeat: $out"; fail=1; }

# 3. New session_id → re-fires (cache is per-session)
nht_sid2="nht2-$$"
nht_cache2="$nht_cache_dir/$nht_sid2"
rm -f "$nht_cache2"
out=$(printf '%s' "$(jq -nc --arg s "$nht_sid2" '{session_id:$s,tool_input:{command:"git log | head -20"}}')" \
       | bash ~/.claude/hooks/no-head-tail-pipe.sh)
echo "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("truncates by line position")' > "$test_out" \
  && echo "OK:   no-head-tail-pipe re-fires on new session_id" \
  || { echo "FAIL: no-head-tail-pipe new session: $out"; fail=1; }

# 4. Non-trigger commands — silent regardless of cache state. Use a unique
# session id so a stray future-trigger bug would still surface.
nht_sid_safe="nht-safe-$$"
for safe_cmd in "ls" "head -n 5 /tmp/x" "cmd | head | wc -l" "cmd || head -n 5 file"; do
  out=$(printf '%s' "$(jq -nc --arg s "$nht_sid_safe" --arg c "$safe_cmd" '{session_id:$s,tool_input:{command:$c}}')" \
         | bash ~/.claude/hooks/no-head-tail-pipe.sh)
  [ -z "$out" ] \
    && echo "OK:   no-head-tail-pipe silent on '$safe_cmd'" \
    || { echo "FAIL: no-head-tail-pipe should be silent on '$safe_cmd': $out"; fail=1; }
done

rm -f "$nht_cache" "$nht_cache2"

# Compact-reset: PostCompact bump should re-arm the one-shot so the hint
# fires again after auto-compact. Behavioral lessons get summarized away
# along with their context, so re-prompting on repeated anti-patterns
# post-compact catches the forgetting.
nht_sid_cmp="nht-cmp-$$"
rm -rf "$nht_cache_dir" /tmp/claude-compact-events
# First fire — gen=0, hint emitted.
out=$(printf '%s' "$(jq -nc --arg s "$nht_sid_cmp" '{session_id:$s,tool_input:{command:"ls | head"}}')" \
       | bash ~/.claude/hooks/no-head-tail-pipe.sh)
echo "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("truncates by line position")' > "$test_out" \
  && echo "OK:   no-head-tail-pipe first fire (compact-rearm setup)" \
  || { echo "FAIL: no-head-tail-pipe first fire for compact test: $out"; fail=1; }
# Second fire same session — silent (one-shot still in effect).
out=$(printf '%s' "$(jq -nc --arg s "$nht_sid_cmp" '{session_id:$s,tool_input:{command:"ls | head"}}')" \
       | bash ~/.claude/hooks/no-head-tail-pipe.sh)
[ -z "$out" ] \
  && echo "OK:   no-head-tail-pipe silent before compact (compact-rearm setup)" \
  || { echo "FAIL: no-head-tail-pipe should be silent before compact: $out"; fail=1; }
# Simulate compaction.
printf '{"session_id":"%s"}' "$nht_sid_cmp" | bash ~/.claude/hooks/compact-bump.sh
# Same session, post-compact — hint re-fires.
out=$(printf '%s' "$(jq -nc --arg s "$nht_sid_cmp" '{session_id:$s,tool_input:{command:"ls | head"}}')" \
       | bash ~/.claude/hooks/no-head-tail-pipe.sh)
echo "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("truncates by line position")' > "$test_out" \
  && echo "OK:   no-head-tail-pipe re-fires after compact-bump" \
  || { echo "FAIL: no-head-tail-pipe should re-fire after compact: $out"; fail=1; }
rm -rf "$nht_cache_dir" /tmp/claude-compact-events

# no-bg-head-tail-pipe: hard-deny when run_in_background=true or timeout >=
# BASH_MAX_TIMEOUT_MS with trailing `| head` / `| tail`. Foreground commands
# under the timeout cap (handled by no-head-tail-pipe) and intermediate
# `| head | wc` are pass-through.
assert_deny no-bg-head-tail-pipe \
  '{"tool_input":{"command":"rg foo | head -n 20","run_in_background":true}}' \
  "Background-risky Bash"
assert_deny no-bg-head-tail-pipe \
  '{"tool_input":{"command":"./server | tail -f","run_in_background":true}}' \
  "Background-risky Bash"
assert_deny_env no-bg-head-tail-pipe \
  '{"tool_input":{"command":"uv run python temp/maker_eda/run_eda.py 2>&1 | tail -50","timeout":600000}}' \
  "Background-risky Bash" BASH_MAX_TIMEOUT_MS 600000
assert_silent_env no-bg-head-tail-pipe \
  '{"tool_input":{"command":"uv run python temp/maker_eda/run_eda.py 2>&1 | tail -50","timeout":599999}}' \
  BASH_MAX_TIMEOUT_MS 600000
assert_silent no-bg-head-tail-pipe \
  '{"tool_input":{"command":"rg foo | head -n 20","run_in_background":false}}'
assert_silent no-bg-head-tail-pipe \
  '{"tool_input":{"command":"rg foo -m 20","run_in_background":true}}'
assert_silent no-bg-head-tail-pipe \
  '{"tool_input":{"command":"rg foo | head | wc -l","run_in_background":true}}'
assert_silent no-bg-head-tail-pipe \
  '{"tool_input":{"command":"rg foo | head -n 20 # BYPASS_BACKGROUND_HEAD_TAIL","run_in_background":true}}'

# warn-auto-bg-head-tail-pipe: PostToolUse advisory when a foreground Bash got
# auto-promoted to background (timeout) and ends with `| head` / `| tail`.
# Explicit run_in_background=true is owned by no-bg-head-tail-pipe.
assert_context warn-auto-bg-head-tail-pipe \
  '{"tool_input":{"command":"rg foo | tail -n 20","run_in_background":false},"tool_response":{"backgroundTaskId":"bg-1"}}' \
  "auto-backgrounded"
assert_silent warn-auto-bg-head-tail-pipe \
  '{"tool_input":{"command":"rg foo | tail -n 20","run_in_background":true},"tool_response":{"backgroundTaskId":"bg-1"}}'
assert_silent warn-auto-bg-head-tail-pipe \
  '{"tool_input":{"command":"rg foo | tail -n 20","run_in_background":false},"tool_response":{}}'
assert_silent warn-auto-bg-head-tail-pipe \
  '{"tool_input":{"command":"./server","run_in_background":false},"tool_response":{"backgroundTaskId":"bg-1"}}'

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
# Third-party provider runtime: prompt-cache dead-zone policy is silent.
assert_silent_env no-schedule-wakeup-deadzone '{"tool_input":{"delaySeconds":600,"reason":"x"}}' ANTHROPIC_BASE_URL "https://api.deepseek.com/anthropic"

# no-multi-question: enforce CLAUDE.md "Ask one question at a time" on AskUserQuestion.
assert_silent no-multi-question '{"tool_input":{"questions":[{"question":"q1?","header":"h"}]}}'
assert_deny no-multi-question '{"tool_input":{"questions":[{"question":"q1?","header":"h"},{"question":"q2?","header":"h"}]}}' "2 questions"
assert_deny no-multi-question '{"tool_input":{"questions":[{"question":"q1?","header":"h"},{"question":"q2?","header":"h"},{"question":"q3?","header":"h"},{"question":"q4?","header":"h"}]}}' "4 questions"
# Boundary: missing/empty questions array — schema would reject upstream, hook stays silent.
assert_silent no-multi-question '{"tool_input":{}}'
assert_silent no-multi-question '{"tool_input":{"questions":[]}}'

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

# 1b. Opus parent + no model + claude-code-guide subagent → inject sonnet too
out=$(printf '%s' "$(jq -nc --arg t "$em_opus" '{transcript_path:$t,tool_input:{subagent_type:"claude-code-guide",prompt:"x"}}')" | bash ~/.claude/hooks/explore-model-sonnet.sh)
echo "$out" | jq -e '.hookSpecificOutput.permissionDecision == "allow" and .hookSpecificOutput.updatedInput.model == "sonnet"' > "$test_out" \
  && echo "OK:   explore-model-sonnet injects sonnet for claude-code-guide opus parent" \
  || { echo "FAIL: explore-model-sonnet claude-code-guide opus-parent inject: $out"; fail=1; }

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

# Subagent skip: agent-* session_id silences the followup hint even with results.
out=$(printf '%s' '{"session_id":"agent-deadbeef","tool_response":{"results":[{"url":"https://x","title":"X"}]}}' | bash ~/.claude/hooks/websearch-followup-hint.sh)
[ -z "$out" ] && echo "OK:   websearch silent in subagent (agent-* sid)" || { echo "FAIL: websearch should skip subagent: $out"; fail=1; }

assert_context reread-after-edit '{"tool_input":{"file_path":"/tmp/x.md"}}' "/tmp/x.md"
assert_context reread-after-edit '{"tool_input":{"file_path":"/tmp/x.py"}}' "/tmp/x.py"
# Basename special-case: CMakeLists.txt routes to CODE despite the .txt extension.
assert_context reread-after-edit '{"tool_input":{"file_path":"/tmp/CMakeLists.txt"}}' "CODE audit"
# Extensionless path → OTHER → silent (deliberate fallback since 5198cee).
assert_silent reread-after-edit '{"tool_input":{"file_path":"/tmp/x"}}'
assert_silent reread-after-edit '{"tool_input":{}}'

assert_context verify-explore-results '{"tool_input":{"subagent_type":"Explore"}}' "Verify subagent"
assert_context verify-explore-results '{"tool_input":{"subagent_type":"claude-code-guide"}}' "Verify subagent"
assert_silent verify-explore-results '{"tool_input":{"subagent_type":"Plan"}}'
assert_silent verify-explore-results '{"tool_input":{"subagent_type":"general-purpose"}}'

echo ""
echo "=== PostToolUse: hooks using emit helper ==="

# cache-keepalive-hint: fires on official-Anthropic backgrounded Bash and Agent;
# silent on foreground and third-party provider runtimes.
assert_context cache-keepalive-hint '{"tool_name":"Bash","tool_input":{"run_in_background":true,"command":"sleep 60"}}' "Background Bash"
assert_context cache-keepalive-hint '{"tool_name":"Agent","tool_input":{"run_in_background":true}}' "Background agent"
assert_context_env cache-keepalive-hint '{"tool_name":"Bash","tool_input":{"run_in_background":true,"command":"sleep 60"}}' "Background Bash" ANTHROPIC_BASE_URL "https://api.anthropic.com"
assert_silent_env cache-keepalive-hint '{"tool_name":"Bash","tool_input":{"run_in_background":true,"command":"sleep 60"}}' ANTHROPIC_BASE_URL "https://api.deepseek.com/anthropic"
assert_silent_env cache-keepalive-hint '{"tool_name":"Agent","tool_input":{"run_in_background":true}}' ANTHROPIC_DEFAULT_MODEL "gpt-5.4"
assert_silent cache-keepalive-hint '{"tool_name":"Bash","tool_input":{"command":"ls"},"tool_response":{}}'
# Subagent session_id (agent-* prefix): silent even on backgrounded Bash.
assert_silent cache-keepalive-hint '{"session_id":"agent-deadbeef1234","tool_name":"Bash","tool_input":{"run_in_background":true,"command":"sleep 60"}}'

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

# Cooldown: time-based. A repeat fire within SYSLOAD_COOLDOWN_SEC of the
# last emit stays silent regardless of which metrics tripped.
out=$(env "${TRIP_ENV[@]}" bash ~/.claude/hooks/inject-system-load.sh <<< "$sysl_in")
[ -z "$out" ] \
  && echo "OK:   inject-system-load silent on repeat (cooldown still active)" \
  || { echo "FAIL: inject-system-load should be silent on repeat: $out"; fail=1; }

# Returning to clean state is a no-op for the cache: nothing tripped, so
# the timestamp from the prior emit is preserved and continues to gate
# subsequent fires.
out=$(env "${SILENT_ENV[@]}" bash ~/.claude/hooks/inject-system-load.sh <<< "$sysl_in")
[ -z "$out" ] \
  && echo "OK:   inject-system-load silent on elevated→clean transition" \
  || { echo "FAIL: inject-system-load clean-after-trip: $out"; fail=1; }

# Re-trip while the cooldown window is still open → silent. Time-based
# cooldown deliberately suppresses a clean→elevated bounce within the
# window (vs. the previous signature-based cache, which would re-emit).
out=$(env "${TRIP_ENV[@]}" bash ~/.claude/hooks/inject-system-load.sh <<< "$sysl_in")
[ -z "$out" ] \
  && echo "OK:   inject-system-load silent on re-trip within cooldown window" \
  || { echo "FAIL: inject-system-load should be silent within cooldown: $out"; fail=1; }

# Re-trip with cooldown forced to 0 → emits immediately, proving the
# gate is purely the timestamp delta.
out=$(env "${TRIP_ENV[@]}" SYSLOAD_COOLDOWN_SEC=0 bash ~/.claude/hooks/inject-system-load.sh <<< "$sysl_in")
echo "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("DISK")' > "$test_out" \
  && echo "OK:   inject-system-load fires again once cooldown elapses (SYSLOAD_COOLDOWN_SEC=0)" \
  || { echo "FAIL: inject-system-load re-trip after cooldown: $out"; fail=1; }

rm -f "$sysl_cache"

# recall-reminder: silent for first (interval-1) turns, fires on the
# interval-th turn, then resets and stays silent again. Counter is per
# session_id under /tmp/claude-recall-reminder/.
rr_sid="rr-$$"
rr_cache="/tmp/claude-recall-reminder/$rr_sid"
rm -f "$rr_cache"
rr_in=$(jq -nc --arg s "$rr_sid" '{session_id:$s}')

# Interval forced to 3 so the test stays small.
out=$(RECALL_REMINDER_INTERVAL=3 bash ~/.claude/hooks/recall-reminder.sh <<< "$rr_in")
[ -z "$out" ] \
  && echo "OK:   recall-reminder silent on turn 1 (interval=3)" \
  || { echo "FAIL: recall-reminder should be silent on turn 1: $out"; fail=1; }

out=$(RECALL_REMINDER_INTERVAL=3 bash ~/.claude/hooks/recall-reminder.sh <<< "$rr_in")
[ -z "$out" ] \
  && echo "OK:   recall-reminder silent on turn 2 (interval=3)" \
  || { echo "FAIL: recall-reminder should be silent on turn 2: $out"; fail=1; }

out=$(RECALL_REMINDER_INTERVAL=3 bash ~/.claude/hooks/recall-reminder.sh <<< "$rr_in")
echo "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("memory/pitfalls.md")' > "$test_out" \
  && echo "OK:   recall-reminder fires on turn 3 (interval=3)" \
  || { echo "FAIL: recall-reminder should fire on turn 3: $out"; fail=1; }

# After fire, counter should be reset → next turn silent again.
out=$(RECALL_REMINDER_INTERVAL=3 bash ~/.claude/hooks/recall-reminder.sh <<< "$rr_in")
[ -z "$out" ] \
  && echo "OK:   recall-reminder silent on turn after reset" \
  || { echo "FAIL: recall-reminder should be silent after reset: $out"; fail=1; }

rm -f "$rr_cache"

# recall-reminder-reset: zeros the counter when Read touches a
# memory page (incl. pitfalls.md), or when Skill invokes memory-add.
rrr_sid="rrr-$$"
rrr_cache="/tmp/claude-recall-reminder/$rrr_sid"
mkdir -p /tmp/claude-recall-reminder

# Pre-seed counter at 7 so we can observe reset to 0.
echo 7 > "$rrr_cache"
rrr_in=$(jq -nc --arg s "$rrr_sid" '{session_id:$s,tool_name:"Read",tool_input:{file_path:"/home/ubuntu/.claude/memory/pitfalls.md"}}')
bash ~/.claude/hooks/recall-reminder-reset.sh <<< "$rrr_in"
[ "$(cat "$rrr_cache")" = "0" ] \
  && echo "OK:   recall-reminder-reset zeros on Read of pitfalls page" \
  || { echo "FAIL: recall-reminder-reset Read pitfalls page: $(cat "$rrr_cache")"; fail=1; }

echo 7 > "$rrr_cache"
rrr_in=$(jq -nc --arg s "$rrr_sid" '{session_id:$s,tool_name:"Read",tool_input:{file_path:"/home/ubuntu/.claude/memory/pages/git-and-commits.md"}}')
bash ~/.claude/hooks/recall-reminder-reset.sh <<< "$rrr_in"
[ "$(cat "$rrr_cache")" = "0" ] \
  && echo "OK:   recall-reminder-reset zeros on Read of memory page" \
  || { echo "FAIL: recall-reminder-reset Read memory page: $(cat "$rrr_cache")"; fail=1; }

# Read of unrelated file → counter untouched.
echo 7 > "$rrr_cache"
rrr_in=$(jq -nc --arg s "$rrr_sid" '{session_id:$s,tool_name:"Read",tool_input:{file_path:"/tmp/other.md"}}')
bash ~/.claude/hooks/recall-reminder-reset.sh <<< "$rrr_in"
[ "$(cat "$rrr_cache")" = "7" ] \
  && echo "OK:   recall-reminder-reset leaves counter on Read of unrelated file" \
  || { echo "FAIL: recall-reminder-reset Read unrelated: $(cat "$rrr_cache")"; fail=1; }

# Skill invocation of memory-add → reset.
echo 7 > "$rrr_cache"
rrr_in=$(jq -nc --arg s "$rrr_sid" '{session_id:$s,tool_name:"Skill",tool_input:{skill:"memory-add"}}')
bash ~/.claude/hooks/recall-reminder-reset.sh <<< "$rrr_in"
[ "$(cat "$rrr_cache")" = "0" ] \
  && echo "OK:   recall-reminder-reset zeros on Skill=memory-add" \
  || { echo "FAIL: recall-reminder-reset Skill memory-add: $(cat "$rrr_cache")"; fail=1; }

# Skill invocation of unrelated skill → counter untouched.
echo 7 > "$rrr_cache"
rrr_in=$(jq -nc --arg s "$rrr_sid" '{session_id:$s,tool_name:"Skill",tool_input:{skill:"read-url"}}')
bash ~/.claude/hooks/recall-reminder-reset.sh <<< "$rrr_in"
[ "$(cat "$rrr_cache")" = "7" ] \
  && echo "OK:   recall-reminder-reset leaves counter on Skill=read-url" \
  || { echo "FAIL: recall-reminder-reset Skill unrelated: $(cat "$rrr_cache")"; fail=1; }

rm -f "$rrr_cache"

echo ""
echo "=== Skill-recall hint hooks ==="

# hint-skill-frontend-design: nudge agent to load the frontend-design skill
# before writing an HTML file. Once-per-session cache (signature: session_id).
hsfd_sid="hsfd-$$"
hsfd_cache="/tmp/claude-skill-hint-frontend-design/$hsfd_sid"
rm -f "$hsfd_cache"

# 1. .html first fire → emit hint
out=$(printf '%s' "$(jq -nc --arg s "$hsfd_sid" '{session_id:$s,tool_input:{file_path:"/tmp/x.html",content:"<html/>"}}')" \
       | bash ~/.claude/hooks/hint-skill-frontend-design.sh)
echo "$out" | jq -e '(.hookSpecificOutput.permissionDecision | not) and (.hookSpecificOutput.additionalContext | contains("frontend-design"))' > "$test_out" \
  && echo "OK:   hint-skill-frontend-design fires on first .html write" \
  || { echo "FAIL: hint-skill-frontend-design first .html: $out"; fail=1; }

# 2. .html second fire same session → cache hit, silent
out=$(printf '%s' "$(jq -nc --arg s "$hsfd_sid" '{session_id:$s,tool_input:{file_path:"/tmp/y.html",content:"<html/>"}}')" \
       | bash ~/.claude/hooks/hint-skill-frontend-design.sh)
[ -z "$out" ] \
  && echo "OK:   hint-skill-frontend-design silent on repeat in same session" \
  || { echo "FAIL: hint-skill-frontend-design should be silent on repeat: $out"; fail=1; }

# 3. Non-html extension → silent
out=$(printf '%s' "$(jq -nc --arg s "$hsfd_sid" '{session_id:$s,tool_input:{file_path:"/tmp/x.py",content:"x=1"}}')" \
       | bash ~/.claude/hooks/hint-skill-frontend-design.sh)
[ -z "$out" ] \
  && echo "OK:   hint-skill-frontend-design silent on .py write" \
  || { echo "FAIL: hint-skill-frontend-design wrong-extension: $out"; fail=1; }

# 4. Different session → hint emitted again (cache is per-session)
hsfd_sid2="hsfd2-$$"
hsfd_cache2="/tmp/claude-skill-hint-frontend-design/$hsfd_sid2"
rm -f "$hsfd_cache2"
out=$(printf '%s' "$(jq -nc --arg s "$hsfd_sid2" '{session_id:$s,tool_input:{file_path:"/tmp/z.html",content:"<html/>"}}')" \
       | bash ~/.claude/hooks/hint-skill-frontend-design.sh)
echo "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("frontend-design")' > "$test_out" \
  && echo "OK:   hint-skill-frontend-design re-fires for new session_id" \
  || { echo "FAIL: hint-skill-frontend-design new session: $out"; fail=1; }

# 5. .htm extension also covered
hsfd_sid3="hsfd3-$$"
out=$(printf '%s' "$(jq -nc --arg s "$hsfd_sid3" '{session_id:$s,tool_input:{file_path:"/tmp/legacy.htm",content:"<html/>"}}')" \
       | bash ~/.claude/hooks/hint-skill-frontend-design.sh)
echo "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("frontend-design")' > "$test_out" \
  && echo "OK:   hint-skill-frontend-design fires on .htm too" \
  || { echo "FAIL: hint-skill-frontend-design .htm: $out"; fail=1; }

rm -f "$hsfd_cache" "$hsfd_cache2" "/tmp/claude-skill-hint-frontend-design/$hsfd_sid3"

# Subagent skip: agent-* session_id silences the hint.
out=$(printf '%s' "$(jq -nc '{session_id:"agent-deadbeef",tool_input:{file_path:"/tmp/x.html",content:"<html/>"}}')" \
       | bash ~/.claude/hooks/hint-skill-frontend-design.sh)
[ -z "$out" ] \
  && echo "OK:   hint-skill-frontend-design silent in subagent (agent-* sid)" \
  || { echo "FAIL: hint-skill-frontend-design should skip subagent: $out"; fail=1; }

# Compact-reset: PostCompact bump re-arms the one-shot post-compact.
hsfd_sid_cmp="hsfd-cmp-$$"
rm -rf /tmp/claude-skill-hint-frontend-design /tmp/claude-compact-events
out=$(printf '%s' "$(jq -nc --arg s "$hsfd_sid_cmp" '{session_id:$s,tool_input:{file_path:"/tmp/a.html",content:"<html/>"}}')" \
       | bash ~/.claude/hooks/hint-skill-frontend-design.sh)
echo "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("frontend-design")' > "$test_out" \
  && echo "OK:   hint-skill-frontend-design first fire (compact-rearm setup)" \
  || { echo "FAIL: hint-skill-frontend-design first fire for compact test: $out"; fail=1; }
out=$(printf '%s' "$(jq -nc --arg s "$hsfd_sid_cmp" '{session_id:$s,tool_input:{file_path:"/tmp/b.html",content:"<html/>"}}')" \
       | bash ~/.claude/hooks/hint-skill-frontend-design.sh)
[ -z "$out" ] && echo "OK:   hint-skill-frontend-design silent before compact" \
  || { echo "FAIL: hint-skill-frontend-design pre-compact silent: $out"; fail=1; }
printf '{"session_id":"%s"}' "$hsfd_sid_cmp" | bash ~/.claude/hooks/compact-bump.sh
out=$(printf '%s' "$(jq -nc --arg s "$hsfd_sid_cmp" '{session_id:$s,tool_input:{file_path:"/tmp/c.html",content:"<html/>"}}')" \
       | bash ~/.claude/hooks/hint-skill-frontend-design.sh)
echo "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("frontend-design")' > "$test_out" \
  && echo "OK:   hint-skill-frontend-design re-fires after compact-bump" \
  || { echo "FAIL: hint-skill-frontend-design should re-fire after compact: $out"; fail=1; }
rm -rf /tmp/claude-skill-hint-frontend-design /tmp/claude-compact-events


# hint-agent-claude-code-guide: nudge the agent to consult the
# claude-code-guide subagent before editing settings.json /
# settings.local.json or files under the agents/, hooks/, skills/
# subtrees of any `.claude/` directory. Other `.claude/` paths
# (CLAUDE.md, memory/, plugins/, ...) are silent.
# Once-per-session cache (signature: session_id).
hccg_sid="hccg-$$"
hccg_cache="/tmp/claude-hint-agent-claude-code-guide/$hccg_sid"
rm -f "$hccg_cache"

# 1. Absolute path under ~/.claude/ → emit hint
out=$(printf '%s' "$(jq -nc --arg s "$hccg_sid" '{session_id:$s,tool_input:{file_path:"/home/bate/.claude/settings.json"}}')" \
       | bash ~/.claude/hooks/hint-agent-claude-code-guide.sh)
echo "$out" | jq -e '(.hookSpecificOutput.permissionDecision | not) and (.hookSpecificOutput.additionalContext | contains("claude-code-guide"))' > "$test_out" \
  && echo "OK:   hint-agent-claude-code-guide fires on first ~/.claude/ edit" \
  || { echo "FAIL: hint-agent-claude-code-guide first edit: $out"; fail=1; }

# 2. Same session, different .claude/ file → cache hit, silent
out=$(printf '%s' "$(jq -nc --arg s "$hccg_sid" '{session_id:$s,tool_input:{file_path:"/home/bate/.claude/hooks/foo.sh"}}')" \
       | bash ~/.claude/hooks/hint-agent-claude-code-guide.sh)
[ -z "$out" ] \
  && echo "OK:   hint-agent-claude-code-guide silent on repeat in same session" \
  || { echo "FAIL: hint-agent-claude-code-guide should be silent on repeat: $out"; fail=1; }

# 3. Project-local <repo>/.claude/... in a new session → fires
hccg_sid2="hccg2-$$"
out=$(printf '%s' "$(jq -nc --arg s "$hccg_sid2" '{session_id:$s,tool_input:{file_path:"/some/repo/.claude/agents/foo.md"}}')" \
       | bash ~/.claude/hooks/hint-agent-claude-code-guide.sh)
echo "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("claude-code-guide")' > "$test_out" \
  && echo "OK:   hint-agent-claude-code-guide fires on project-local .claude/ path" \
  || { echo "FAIL: hint-agent-claude-code-guide project-local: $out"; fail=1; }

# 4. Relative leading-segment .claude/... → fires
hccg_sid3="hccg3-$$"
out=$(printf '%s' "$(jq -nc --arg s "$hccg_sid3" '{session_id:$s,tool_input:{file_path:".claude/skills/x.md"}}')" \
       | bash ~/.claude/hooks/hint-agent-claude-code-guide.sh)
echo "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("claude-code-guide")' > "$test_out" \
  && echo "OK:   hint-agent-claude-code-guide fires on relative .claude/ path" \
  || { echo "FAIL: hint-agent-claude-code-guide relative path: $out"; fail=1; }

# 5. Unrelated path → silent
hccg_sid4="hccg4-$$"
out=$(printf '%s' "$(jq -nc --arg s "$hccg_sid4" '{session_id:$s,tool_input:{file_path:"/tmp/foo.py"}}')" \
       | bash ~/.claude/hooks/hint-agent-claude-code-guide.sh)
[ -z "$out" ] \
  && echo "OK:   hint-agent-claude-code-guide silent on unrelated path" \
  || { echo "FAIL: hint-agent-claude-code-guide unrelated: $out"; fail=1; }

# 6. FP guard: .claudeignore must NOT trigger (no `/` after `.claude`)
hccg_sid5="hccg5-$$"
out=$(printf '%s' "$(jq -nc --arg s "$hccg_sid5" '{session_id:$s,tool_input:{file_path:"/home/bate/.claudeignore"}}')" \
       | bash ~/.claude/hooks/hint-agent-claude-code-guide.sh)
[ -z "$out" ] \
  && echo "OK:   hint-agent-claude-code-guide silent on .claudeignore (FP guard)" \
  || { echo "FAIL: hint-agent-claude-code-guide .claudeignore FP: $out"; fail=1; }

# 7. FP guard: foo.claude/bar.txt must NOT trigger (no `/` before `.claude`)
hccg_sid6="hccg6-$$"
out=$(printf '%s' "$(jq -nc --arg s "$hccg_sid6" '{session_id:$s,tool_input:{file_path:"/home/bate/foo.claude/bar.txt"}}')" \
       | bash ~/.claude/hooks/hint-agent-claude-code-guide.sh)
[ -z "$out" ] \
  && echo "OK:   hint-agent-claude-code-guide silent on foo.claude/ (FP guard)" \
  || { echo "FAIL: hint-agent-claude-code-guide foo.claude FP: $out"; fail=1; }

# 8. CLAUDE.md is prose guidance, not Claude Code schema → silent
hccg_sid7="hccg7-$$"
out=$(printf '%s' "$(jq -nc --arg s "$hccg_sid7" '{session_id:$s,tool_input:{file_path:"/home/bate/.claude/CLAUDE.md"}}')" \
       | bash ~/.claude/hooks/hint-agent-claude-code-guide.sh)
[ -z "$out" ] \
  && echo "OK:   hint-agent-claude-code-guide silent on CLAUDE.md" \
  || { echo "FAIL: hint-agent-claude-code-guide CLAUDE.md FP: $out"; fail=1; }

# 9. settings.local.json is in the allow-list → fires
hccg_sid8="hccg8-$$"
out=$(printf '%s' "$(jq -nc --arg s "$hccg_sid8" '{session_id:$s,tool_input:{file_path:"/home/bate/.claude/settings.local.json"}}')" \
       | bash ~/.claude/hooks/hint-agent-claude-code-guide.sh)
echo "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("claude-code-guide")' > "$test_out" \
  && echo "OK:   hint-agent-claude-code-guide fires on settings.local.json" \
  || { echo "FAIL: hint-agent-claude-code-guide settings.local.json: $out"; fail=1; }

# 10. .claude/plugins/* is outside the allow-list (settings/agents/hooks/skills) → silent
hccg_sid9="hccg9-$$"
out=$(printf '%s' "$(jq -nc --arg s "$hccg_sid9" '{session_id:$s,tool_input:{file_path:"/home/bate/.claude/plugins/foo.json"}}')" \
       | bash ~/.claude/hooks/hint-agent-claude-code-guide.sh)
[ -z "$out" ] \
  && echo "OK:   hint-agent-claude-code-guide silent on .claude/plugins/" \
  || { echo "FAIL: hint-agent-claude-code-guide plugins FP: $out"; fail=1; }

# 11. .claude/memory/*.md is outside the allow-list → silent
hccg_sid10="hccg10-$$"
out=$(printf '%s' "$(jq -nc --arg s "$hccg_sid10" '{session_id:$s,tool_input:{file_path:"/home/bate/.claude/memory/BUILD.md"}}')" \
       | bash ~/.claude/hooks/hint-agent-claude-code-guide.sh)
[ -z "$out" ] \
  && echo "OK:   hint-agent-claude-code-guide silent on .claude/memory/" \
  || { echo "FAIL: hint-agent-claude-code-guide memory FP: $out"; fail=1; }

rm -f "$hccg_cache" \
      "/tmp/claude-hint-agent-claude-code-guide/$hccg_sid2" \
      "/tmp/claude-hint-agent-claude-code-guide/$hccg_sid3" \
      "/tmp/claude-hint-agent-claude-code-guide/$hccg_sid7" \
      "/tmp/claude-hint-agent-claude-code-guide/$hccg_sid8"

# Subagent skip: agent-* session_id silences the hint. Most subagents lack
# the Agent tool and can't act on the "spawn claude-code-guide subagent" advice.
out=$(printf '%s' "$(jq -nc '{session_id:"agent-deadbeef",tool_input:{file_path:"/home/bate/.claude/settings.json"}}')" \
       | bash ~/.claude/hooks/hint-agent-claude-code-guide.sh)
[ -z "$out" ] \
  && echo "OK:   hint-agent-claude-code-guide silent in subagent (agent-* sid)" \
  || { echo "FAIL: hint-agent-claude-code-guide should skip subagent: $out"; fail=1; }

# Compact-reset: PostCompact bump re-arms the one-shot post-compact.
hccg_sid_cmp="hccg-cmp-$$"
rm -rf /tmp/claude-hint-agent-claude-code-guide /tmp/claude-compact-events
out=$(printf '%s' "$(jq -nc --arg s "$hccg_sid_cmp" '{session_id:$s,tool_input:{file_path:"/home/bate/.claude/settings.json"}}')" \
       | bash ~/.claude/hooks/hint-agent-claude-code-guide.sh)
echo "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("claude-code-guide")' > "$test_out" \
  && echo "OK:   hint-agent-claude-code-guide first fire (compact-rearm setup)" \
  || { echo "FAIL: hint-agent-claude-code-guide first fire for compact test: $out"; fail=1; }
out=$(printf '%s' "$(jq -nc --arg s "$hccg_sid_cmp" '{session_id:$s,tool_input:{file_path:"/home/bate/.claude/hooks/foo.sh"}}')" \
       | bash ~/.claude/hooks/hint-agent-claude-code-guide.sh)
[ -z "$out" ] && echo "OK:   hint-agent-claude-code-guide silent before compact" \
  || { echo "FAIL: hint-agent-claude-code-guide pre-compact silent: $out"; fail=1; }
printf '{"session_id":"%s"}' "$hccg_sid_cmp" | bash ~/.claude/hooks/compact-bump.sh
out=$(printf '%s' "$(jq -nc --arg s "$hccg_sid_cmp" '{session_id:$s,tool_input:{file_path:"/home/bate/.claude/skills/bar.md"}}')" \
       | bash ~/.claude/hooks/hint-agent-claude-code-guide.sh)
echo "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("claude-code-guide")' > "$test_out" \
  && echo "OK:   hint-agent-claude-code-guide re-fires after compact-bump" \
  || { echo "FAIL: hint-agent-claude-code-guide should re-fire after compact: $out"; fail=1; }
rm -rf /tmp/claude-hint-agent-claude-code-guide /tmp/claude-compact-events


# hint-skill-jina-ai: nudge agent to load the jina-ai skill before calling
# WebSearch. Once-per-session cache (signature: session_id).
hsja_sid="hsja-$$"
hsja_cache="/tmp/claude-skill-hint-jina-ai/$hsja_sid"
rm -f "$hsja_cache"

# 1. WebSearch first fire → emit hint
out=$(printf '%s' "$(jq -nc --arg s "$hsja_sid" '{session_id:$s,tool_name:"WebSearch",tool_input:{query:"foo"}}')" \
       | bash ~/.claude/hooks/hint-skill-jina-ai.sh)
echo "$out" | jq -e '(.hookSpecificOutput.permissionDecision | not) and (.hookSpecificOutput.additionalContext | contains("/jina-ai"))' > "$test_out" \
  && echo "OK:   hint-skill-jina-ai fires on first WebSearch call" \
  || { echo "FAIL: hint-skill-jina-ai first WebSearch: $out"; fail=1; }

# 2. WebSearch second fire same session → cache hit, silent
out=$(printf '%s' "$(jq -nc --arg s "$hsja_sid" '{session_id:$s,tool_name:"WebSearch",tool_input:{query:"bar"}}')" \
       | bash ~/.claude/hooks/hint-skill-jina-ai.sh)
[ -z "$out" ] \
  && echo "OK:   hint-skill-jina-ai silent on repeat in same session" \
  || { echo "FAIL: hint-skill-jina-ai should be silent on repeat: $out"; fail=1; }

# 3. Different session → hint re-fires (cache is per-session)
hsja_sid2="hsja2-$$"
hsja_cache2="/tmp/claude-skill-hint-jina-ai/$hsja_sid2"
rm -f "$hsja_cache2"
out=$(printf '%s' "$(jq -nc --arg s "$hsja_sid2" '{session_id:$s,tool_name:"WebSearch",tool_input:{query:"baz"}}')" \
       | bash ~/.claude/hooks/hint-skill-jina-ai.sh)
echo "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("/jina-ai")' > "$test_out" \
  && echo "OK:   hint-skill-jina-ai re-fires for new session_id" \
  || { echo "FAIL: hint-skill-jina-ai new session: $out"; fail=1; }

rm -f "$hsja_cache" "$hsja_cache2"

# Subagent skip: agent-* session_id silences the hint.
out=$(printf '%s' "$(jq -nc '{session_id:"agent-deadbeef",tool_name:"WebSearch",tool_input:{query:"foo"}}')" \
       | bash ~/.claude/hooks/hint-skill-jina-ai.sh)
[ -z "$out" ] \
  && echo "OK:   hint-skill-jina-ai silent in subagent (agent-* sid)" \
  || { echo "FAIL: hint-skill-jina-ai should skip subagent: $out"; fail=1; }

# Compact-reset: PostCompact bump re-arms the one-shot post-compact.
hsja_sid_cmp="hsja-cmp-$$"
rm -rf /tmp/claude-skill-hint-jina-ai /tmp/claude-compact-events
out=$(printf '%s' "$(jq -nc --arg s "$hsja_sid_cmp" '{session_id:$s,tool_name:"WebSearch",tool_input:{query:"foo"}}')" \
       | bash ~/.claude/hooks/hint-skill-jina-ai.sh)
echo "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("/jina-ai")' > "$test_out" \
  && echo "OK:   hint-skill-jina-ai first fire (compact-rearm setup)" \
  || { echo "FAIL: hint-skill-jina-ai first fire for compact test: $out"; fail=1; }
out=$(printf '%s' "$(jq -nc --arg s "$hsja_sid_cmp" '{session_id:$s,tool_name:"WebSearch",tool_input:{query:"bar"}}')" \
       | bash ~/.claude/hooks/hint-skill-jina-ai.sh)
[ -z "$out" ] && echo "OK:   hint-skill-jina-ai silent before compact" \
  || { echo "FAIL: hint-skill-jina-ai pre-compact silent: $out"; fail=1; }
printf '{"session_id":"%s"}' "$hsja_sid_cmp" | bash ~/.claude/hooks/compact-bump.sh
out=$(printf '%s' "$(jq -nc --arg s "$hsja_sid_cmp" '{session_id:$s,tool_name:"WebSearch",tool_input:{query:"baz"}}')" \
       | bash ~/.claude/hooks/hint-skill-jina-ai.sh)
echo "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("/jina-ai")' > "$test_out" \
  && echo "OK:   hint-skill-jina-ai re-fires after compact-bump" \
  || { echo "FAIL: hint-skill-jina-ai should re-fire after compact: $out"; fail=1; }
rm -rf /tmp/claude-skill-hint-jina-ai /tmp/claude-compact-events


# hint-skill-read-url: nudge agent to load the read-url skill before calling
# WebFetch. Once-per-session cache (signature: session_id).
hsru_sid="hsru-$$"
hsru_cache="/tmp/claude-skill-hint-read-url/$hsru_sid"
rm -f "$hsru_cache"

# 1. WebFetch first fire → emit hint
out=$(printf '%s' "$(jq -nc --arg s "$hsru_sid" '{session_id:$s,tool_name:"WebFetch",tool_input:{url:"https://example.com"}}')" \
       | bash ~/.claude/hooks/hint-skill-read-url.sh)
echo "$out" | jq -e '(.hookSpecificOutput.permissionDecision | not) and (.hookSpecificOutput.additionalContext | contains("/read-url"))' > "$test_out" \
  && echo "OK:   hint-skill-read-url fires on first WebFetch call" \
  || { echo "FAIL: hint-skill-read-url first WebFetch: $out"; fail=1; }

# 2. WebFetch second fire same session → cache hit, silent
out=$(printf '%s' "$(jq -nc --arg s "$hsru_sid" '{session_id:$s,tool_name:"WebFetch",tool_input:{url:"https://example.org"}}')" \
       | bash ~/.claude/hooks/hint-skill-read-url.sh)
[ -z "$out" ] \
  && echo "OK:   hint-skill-read-url silent on repeat in same session" \
  || { echo "FAIL: hint-skill-read-url should be silent on repeat: $out"; fail=1; }

# 3. Different session → hint re-fires (cache is per-session)
hsru_sid2="hsru2-$$"
hsru_cache2="/tmp/claude-skill-hint-read-url/$hsru_sid2"
rm -f "$hsru_cache2"
out=$(printf '%s' "$(jq -nc --arg s "$hsru_sid2" '{session_id:$s,tool_name:"WebFetch",tool_input:{url:"https://example.net"}}')" \
       | bash ~/.claude/hooks/hint-skill-read-url.sh)
echo "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("/read-url")' > "$test_out" \
  && echo "OK:   hint-skill-read-url re-fires for new session_id" \
  || { echo "FAIL: hint-skill-read-url new session: $out"; fail=1; }

rm -f "$hsru_cache" "$hsru_cache2"

# Subagent skip: agent-* session_id silences the hint.
out=$(printf '%s' "$(jq -nc '{session_id:"agent-deadbeef",tool_name:"WebFetch",tool_input:{url:"https://example.com"}}')" \
       | bash ~/.claude/hooks/hint-skill-read-url.sh)
[ -z "$out" ] \
  && echo "OK:   hint-skill-read-url silent in subagent (agent-* sid)" \
  || { echo "FAIL: hint-skill-read-url should skip subagent: $out"; fail=1; }

# Compact-reset: PostCompact bump re-arms the one-shot post-compact.
hsru_sid_cmp="hsru-cmp-$$"
rm -rf /tmp/claude-skill-hint-read-url /tmp/claude-compact-events
out=$(printf '%s' "$(jq -nc --arg s "$hsru_sid_cmp" '{session_id:$s,tool_name:"WebFetch",tool_input:{url:"https://example.com"}}')" \
       | bash ~/.claude/hooks/hint-skill-read-url.sh)
echo "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("/read-url")' > "$test_out" \
  && echo "OK:   hint-skill-read-url first fire (compact-rearm setup)" \
  || { echo "FAIL: hint-skill-read-url first fire for compact test: $out"; fail=1; }
out=$(printf '%s' "$(jq -nc --arg s "$hsru_sid_cmp" '{session_id:$s,tool_name:"WebFetch",tool_input:{url:"https://example.org"}}')" \
       | bash ~/.claude/hooks/hint-skill-read-url.sh)
[ -z "$out" ] && echo "OK:   hint-skill-read-url silent before compact" \
  || { echo "FAIL: hint-skill-read-url pre-compact silent: $out"; fail=1; }
printf '{"session_id":"%s"}' "$hsru_sid_cmp" | bash ~/.claude/hooks/compact-bump.sh
out=$(printf '%s' "$(jq -nc --arg s "$hsru_sid_cmp" '{session_id:$s,tool_name:"WebFetch",tool_input:{url:"https://example.net"}}')" \
       | bash ~/.claude/hooks/hint-skill-read-url.sh)
echo "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("/read-url")' > "$test_out" \
  && echo "OK:   hint-skill-read-url re-fires after compact-bump" \
  || { echo "FAIL: hint-skill-read-url should re-fire after compact: $out"; fail=1; }
rm -rf /tmp/claude-skill-hint-read-url /tmp/claude-compact-events

# === prefer-limited-read ===
plr_big_lines=$(mktemp /tmp/plr-big-lines-XXXXXX)
plr_big_bytes=$(mktemp /tmp/plr-big-bytes-XXXXXX)
plr_small=$(mktemp /tmp/plr-small-XXXXXX)
# 400 lines × ~3 bytes/line ≈ 1.6 KB — triggers by line count, NOT by bytes.
seq 1 400 > "$plr_big_lines"
# 50 lines × 401 bytes ≈ 20 KB — triggers by bytes, NOT by line count.
awk 'BEGIN{for(i=0;i<50;i++){for(j=0;j<400;j++)printf"x";print""}}' > "$plr_big_bytes"
# 50 lines × ~3 bytes — under both thresholds, allowed.
seq 1 50 > "$plr_small"

assert_deny   prefer-limited-read "$(jq -n --arg fp "$plr_big_lines" '{tool_input:{file_path:$fp}}')" "400 lines"
assert_deny   prefer-limited-read "$(jq -n --arg fp "$plr_big_bytes" '{tool_input:{file_path:$fp}}')" "KB"
assert_silent prefer-limited-read "$(jq -n --arg fp "$plr_big_lines" '{tool_input:{file_path:$fp,limit:100}}')"
assert_silent prefer-limited-read "$(jq -n --arg fp "$plr_big_bytes" '{tool_input:{file_path:$fp,limit:100}}')"
assert_silent prefer-limited-read "$(jq -n --arg fp "$plr_small" '{tool_input:{file_path:$fp}}')"
assert_silent prefer-limited-read '{"tool_input":{"file_path":"/tmp/does-not-exist-plr"}}'
assert_silent prefer-limited-read '{"tool_input":{}}'

rm -f "$plr_big_lines" "$plr_big_bytes" "$plr_small"

# === hint-fork-on-bloat ===
# 60 KB string payload — single call crosses the 50 KB threshold.
hfb_big_payload=$(awk 'BEGIN{for(i=0;i<60;i++){for(j=0;j<1024;j++)printf"x";print""}}')
# 1 KB payload — well below threshold, two calls still silent.
hfb_small_payload=$(awk 'BEGIN{for(j=0;j<1024;j++)printf"x"}')

# Clean any stale state from prior runs.
rm -rf /tmp/claude-hint-fork-bloat

assert_silent hint-fork-on-bloat "$(jq -n --arg p "$hfb_small_payload" '{session_id:"hfb_small_sess",tool_response:$p}')"
assert_silent hint-fork-on-bloat "$(jq -n --arg p "$hfb_small_payload" '{session_id:"hfb_small_sess",tool_response:$p}')"
assert_context hint-fork-on-bloat "$(jq -n --arg p "$hfb_big_payload" '{session_id:"hfb_big_sess",tool_response:$p}')" "Fork-first on Surveys"
# Already fired in hfb_big_sess: subsequent calls silent (one-shot).
assert_silent hint-fork-on-bloat "$(jq -n --arg p "$hfb_big_payload" '{session_id:"hfb_big_sess",tool_response:$p}')"
# Missing session_id: silent.
assert_silent hint-fork-on-bloat "$(jq -n --arg p "$hfb_big_payload" '{tool_response:$p}')"
# Empty tool_response: silent.
assert_silent hint-fork-on-bloat '{"session_id":"hfb_empty_sess","tool_response":""}'
# Subagent session_id (agent-* prefix): silent even with big payload.
assert_silent hint-fork-on-bloat "$(jq -n --arg p "$hfb_big_payload" '{session_id:"agent-deadbeef1234",tool_response:$p}')"

# Compact-reset: after firing, a PostCompact bump should re-arm the hint so
# the next bloat cycle fires again. Uses the shared compact-bump generation
# file owned by compact-bump.sh (PostCompact).
rm -rf /tmp/claude-hint-fork-bloat /tmp/claude-compact-events
# First fire — gen starts at 0 (no PostCompact yet).
assert_context hint-fork-on-bloat "$(jq -n --arg p "$hfb_big_payload" '{session_id:"hfb_compact_sess",tool_response:$p}')" "Fork-first on Surveys"
# Same session, no compact yet — silent (one-shot still in effect).
assert_silent hint-fork-on-bloat "$(jq -n --arg p "$hfb_big_payload" '{session_id:"hfb_compact_sess",tool_response:$p}')"
# Simulate a compaction by invoking compact-bump.sh — gen 0 → 1.
printf '{"session_id":"hfb_compact_sess"}' | bash ~/.claude/hooks/compact-bump.sh
# Now the hint re-fires because current_gen (1) > prev_gen (0).
assert_context hint-fork-on-bloat "$(jq -n --arg p "$hfb_big_payload" '{session_id:"hfb_compact_sess",tool_response:$p}')" "Fork-first on Surveys"
# After re-fire, silent again on the next call.
assert_silent hint-fork-on-bloat "$(jq -n --arg p "$hfb_big_payload" '{session_id:"hfb_compact_sess",tool_response:$p}')"

rm -rf /tmp/claude-hint-fork-bloat /tmp/claude-compact-events

# === compact-bump ===
# PostCompact hook: increments per-session generation counter. Silent stdout;
# state is the file. Verify increment, missing-session-id silent no-op.
rm -rf /tmp/claude-compact-events
assert_silent compact-bump '{"session_id":"cb_sess"}'
[ "$(cat /tmp/claude-compact-events/cb_sess.gen 2>&1)" = "1" ] \
  && echo "OK:   compact-bump gen 0 → 1" \
  || { echo "FAIL: compact-bump first call should set gen=1"; fail=1; }
assert_silent compact-bump '{"session_id":"cb_sess"}'
[ "$(cat /tmp/claude-compact-events/cb_sess.gen 2>&1)" = "2" ] \
  && echo "OK:   compact-bump gen 1 → 2" \
  || { echo "FAIL: compact-bump second call should set gen=2"; fail=1; }
# Missing session_id: silent and no file written.
assert_silent compact-bump '{}'
[ -z "$(ls /tmp/claude-compact-events/ 2>&1 | rg -v '^cb_sess')" ] \
  && echo "OK:   compact-bump silent on missing session_id" \
  || { echo "FAIL: compact-bump should not write file without session_id"; fail=1; }

rm -rf /tmp/claude-compact-events

# hint-skill-pueue: block pueue commands until /pueue skill loaded.
# Denies once per session per compact; skill load unlocks; subagents pass.
hsp_sid="hsp-$$"
rm -rf /tmp/claude-pueue-skill-loaded /tmp/claude-pueue-skill-hint /tmp/claude-compact-events

# 1. First pueue command → deny with /pueue mention
out=$(jq -nc --arg s "$hsp_sid" '{session_id:$s,tool_name:"Bash",tool_input:{command:"pueue add -- echo hi"}}' \
       | bash ~/.claude/hooks/hint-skill-pueue.sh)
echo "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny" and (.hookSpecificOutput.permissionDecisionReason | contains("/pueue"))' > "$test_out" \
  && echo "OK:   hint-skill-pueue denies first pueue command" \
  || { echo "FAIL: hint-skill-pueue first pueue: $out"; fail=1; }

# 2. Second pueue command same session (hint already given) → one-shot, allow
out=$(jq -nc --arg s "$hsp_sid" '{session_id:$s,tool_name:"Bash",tool_input:{command:"pueue status"}}' \
       | bash ~/.claude/hooks/hint-skill-pueue.sh)
[ -z "$out" ] \
  && echo "OK:   hint-skill-pueue silent on repeat (one-shot)" \
  || { echo "FAIL: hint-skill-pueue should be silent after one-shot: $out"; fail=1; }

# 3. Non-pueue command → always silent
out=$(jq -nc --arg s "$hsp_sid" '{session_id:$s,tool_name:"Bash",tool_input:{command:"echo hello"}}' \
       | bash ~/.claude/hooks/hint-skill-pueue.sh)
[ -z "$out" ] \
  && echo "OK:   hint-skill-pueue silent for non-pueue command" \
  || { echo "FAIL: hint-skill-pueue should ignore non-pueue: $out"; fail=1; }

# 4. Subagent (agent-* sid) → always silent
out=$(jq -nc '{session_id:"agent-deadbeef",tool_name:"Bash",tool_input:{command:"pueue add -- foo"}}' \
       | bash ~/.claude/hooks/hint-skill-pueue.sh)
[ -z "$out" ] \
  && echo "OK:   hint-skill-pueue silent for subagent" \
  || { echo "FAIL: hint-skill-pueue should skip subagent: $out"; fail=1; }

# 5. Skill-unlock: track-pueue-skill-load sets flag → hint hook allows
hsp_sid2="hsp2-$$"
rm -rf /tmp/claude-pueue-skill-loaded /tmp/claude-pueue-skill-hint
jq -nc --arg s "$hsp_sid2" '{session_id:$s,tool_name:"Skill",tool_input:{skill:"pueue"}}' \
  | bash ~/.claude/hooks/track-pueue-skill-load.sh
out=$(jq -nc --arg s "$hsp_sid2" '{session_id:$s,tool_name:"Bash",tool_input:{command:"pueue status"}}' \
       | bash ~/.claude/hooks/hint-skill-pueue.sh)
[ -z "$out" ] \
  && echo "OK:   hint-skill-pueue allows after skill loaded" \
  || { echo "FAIL: hint-skill-pueue should allow once skill loaded: $out"; fail=1; }

# 6. track-pueue-skill-load ignores non-pueue skills
hsp_sid3="hsp3-$$"
rm -rf /tmp/claude-pueue-skill-loaded /tmp/claude-pueue-skill-hint
jq -nc --arg s "$hsp_sid3" '{session_id:$s,tool_name:"Skill",tool_input:{skill:"jina-ai"}}' \
  | bash ~/.claude/hooks/track-pueue-skill-load.sh
[ ! -f "/tmp/claude-pueue-skill-loaded/$hsp_sid3" ] \
  && echo "OK:   track-pueue-skill-load ignores non-pueue skill" \
  || { echo "FAIL: track-pueue-skill-load should not set flag for other skills"; fail=1; }

# 7. Compact re-arm: deny → silent → compact-bump → deny again
hsp_sid4="hsp4-$$"
rm -rf /tmp/claude-pueue-skill-loaded /tmp/claude-pueue-skill-hint /tmp/claude-compact-events
out=$(jq -nc --arg s "$hsp_sid4" '{session_id:$s,tool_name:"Bash",tool_input:{command:"pueue add -- echo"}}' \
       | bash ~/.claude/hooks/hint-skill-pueue.sh)
echo "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' > "$test_out" \
  && echo "OK:   hint-skill-pueue first deny (compact-rearm setup)" \
  || { echo "FAIL: hint-skill-pueue first deny for compact test: $out"; fail=1; }
out=$(jq -nc --arg s "$hsp_sid4" '{session_id:$s,tool_name:"Bash",tool_input:{command:"pueue status"}}' \
       | bash ~/.claude/hooks/hint-skill-pueue.sh)
[ -z "$out" ] && echo "OK:   hint-skill-pueue silent before compact" \
  || { echo "FAIL: hint-skill-pueue pre-compact silent: $out"; fail=1; }
printf '{"session_id":"%s"}' "$hsp_sid4" | bash ~/.claude/hooks/compact-bump.sh
out=$(jq -nc --arg s "$hsp_sid4" '{session_id:$s,tool_name:"Bash",tool_input:{command:"pueue add -- echo"}}' \
       | bash ~/.claude/hooks/hint-skill-pueue.sh)
echo "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' > "$test_out" \
  && echo "OK:   hint-skill-pueue re-denies after compact-bump" \
  || { echo "FAIL: hint-skill-pueue should re-deny after compact: $out"; fail=1; }

# 8. gen-seen sync: skill loaded after compact → pre-bash hook doesn't wipe flag
hsp_sid5="hsp5-$$"
rm -rf /tmp/claude-pueue-skill-loaded /tmp/claude-pueue-skill-hint /tmp/claude-compact-events
printf '{"session_id":"%s"}' "$hsp_sid5" | bash ~/.claude/hooks/compact-bump.sh
jq -nc --arg s "$hsp_sid5" '{session_id:$s,tool_name:"Skill",tool_input:{skill:"pueue"}}' \
  | bash ~/.claude/hooks/track-pueue-skill-load.sh
out=$(jq -nc --arg s "$hsp_sid5" '{session_id:$s,tool_name:"Bash",tool_input:{command:"pueue status"}}' \
       | bash ~/.claude/hooks/hint-skill-pueue.sh)
[ -z "$out" ] \
  && echo "OK:   hint-skill-pueue allows when skill loaded after compact" \
  || { echo "FAIL: hint-skill-pueue should not wipe skill flag set post-compact: $out"; fail=1; }

rm -rf /tmp/claude-pueue-skill-loaded /tmp/claude-pueue-skill-hint /tmp/claude-compact-events

echo ""
rm -f "$test_out"

echo ""
if [ $fail -eq 0 ]; then
  echo "ALL TESTS PASS"
else
  echo "$fail failures"
fi
exit $fail
