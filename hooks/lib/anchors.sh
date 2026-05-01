#!/usr/bin/bash
# Shared command-position regex anchors for PreToolUse Bash hooks.
#
# A "command position" is any spot in the bash command string where a fresh
# command starts: line start, after `&&` / `;` / `|` / `(` / `{`, the body of
# `do` / `then` / `else`, and (optionally) under `sudo`. Every blocking hook
# that targets a tool name (`cp`, `mv`, `rm`, `python3`, …) must check for
# the tool at command position — otherwise `git rm`, `npm rm`, `xargs grep`,
# identifiers containing the name, or quoted strings would all false-positive
# or false-negative.
#
# Patterns are PCRE — use with `grep -qP`. They expand into a larger regex,
# typically as: grep -qP "(${CMD_ANCHOR_SUDO}|${CMD_WRAPPER})TOOL${CMD_TRAIL}"
# where TOOL is the literal tool name (e.g. `rm`, `cp`, `mv`).
#
# CMD_ANCHOR_BASIC — direct command position, no sudo.
#   Use when sudo is irrelevant (tool-style suggestions, not safety blocks).
#
# CMD_ANCHOR_SUDO  — direct command position with optional `sudo`.
#   Use for safety blocks where `sudo cp` is at least as dangerous as `cp`.
#
# CMD_WRAPPER      — indirect invocation through a shell evaluator:
#       bash -c …   — `-c` required (so `bash script.sh` with a script named
#                     `cp`/`rm` is not flagged); flags before `-c` allowed
#                     (e.g. `bash --norc -c rm`).
#       sh -c …     — same.
#       eval …      — entire arg string is shell code.
#       xargs …     — invokes the next arg as a command.
#   An optional opening quote (`'` or `"`) and an optional inner `sudo` follow.
#   Use as alternation with CMD_ANCHOR_SUDO when indirect invocation matters.
#
#   Known limitation: `bash -lc rm` (combined `-l` + `-c`) is NOT matched. The
#   regex requires a literal `-c` token. Combined-flag forms are uncommon in
#   agent-issued commands; the bypass marker handles them.
#
# CMD_TRAIL        — trailing lookahead. Accepts whitespace, `;` `&` `|`,
#   closing quote (`'` or `"`), or end-of-string. Lets `eval "rm foo"` and
#   `bash -c "rm"` register as terminated tool invocations.
#
# Inherent limitation: regex cannot shell-parse. The tightened WRAPPER (which
# requires the wrapper tool to sit at command position, not just `\b…\b`)
# eliminates the most common FP class — `echo "use eval rm here"` no longer
# trips, because mid-string `eval` is preceded by space, not an anchor char.
# What still trips: a literal `|` byte followed by a real wrapper invocation,
# e.g. `grep 'foo|bash -c rm' file` — the regex sees `|bash -c rm` as a
# pipe-into-wrapper. Bypass marker is the documented escape — see lib/README.md.

CMD_ANCHOR_BASIC='(^|&&|;|\||\(|\{)\s*((do|then|else)\s+)?'
# CMD_ANCHOR_SUDO accepts an optional `sudo` invocation including any sudo
# flags. With-arg short opts (-C -D -g -h -p -r -t -T -u -U) consume their
# argument; bare `-flag` (including combined `-nE`, attached `-uroot`, and
# long `--non-interactive`) consume one token. This catches `sudo srm`,
# `sudo -n srm`, `sudo -u root srm`, `sudo --non-interactive srm`. Not
# modeled: `--longopt value` (use `--longopt=value`).
CMD_ANCHOR_SUDO="${CMD_ANCHOR_BASIC}(sudo\s+((-[CDghprtTuU]\s+\S+|-\S+)\s+)*)?"
# CMD_WRAPPER reuses CMD_ANCHOR_SUDO so the wrapper itself must be at command
# position. Catches `sudo bash -c rm`, `; eval rm`, `do bash -c rm`. Also
# eliminates the `echo "use eval rm here"` FP class — `eval` in mid-string
# is preceded by a space, not an anchor, so it no longer triggers.
CMD_WRAPPER="${CMD_ANCHOR_SUDO}((bash|sh)\s+(-\S+\s+)*-c\s+|eval\s+|xargs\s+(-\S+\s+)*)"'['\''"]?(sudo\s+)?'

# CMD_WRAPPER_SSH — ssh-wrapped invocation: `ssh [options] host CMD`.
# Use as an additional alternation alongside CMD_WRAPPER for safety blocks
# where remote execution is also a hazard (e.g. `ssh host srm /x` destroys
# data just as irrecoverably as a local `srm`). DO NOT add to tool-suggestion
# hooks (no-cat-write, no-head-read, no-sed-print, no-pip-npm) — Read/Write
# operate locally and have no remote substitute, so blocking ssh-wrapped
# forms would leave the user with no alternative.
#
# The option-eater handles `-X arg` for short opts that take an argument
# (-b -B -c -D -e -E -F -I -i -J -L -l -m -O -o -p -Q -R -S -W -w) and bare
# `-flag` (including combined forms like `-CAfN` and attached `-p22`).
# Not modeled: `--longopt value` (use `--longopt=value`), trailing `--`,
# quoted hostnames with spaces, mid-host options like `ssh host -i key cmd`.
CMD_WRAPPER_SSH="${CMD_ANCHOR_SUDO}ssh\s+((-[bBcDeEFIiJLlmOopQRSWw]\s+\S+|-\S+)\s+)*\S+\s+"'['\''"]?(sudo\s+)?'

CMD_TRAIL='(?=[\s;&|'\''"]|$)'
