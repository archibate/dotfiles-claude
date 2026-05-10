#!/usr/bin/env bash
set -euo pipefail

ARG="${MEMADD_ARG:-}"

if [ -z "$ARG" ]; then
  echo "ERROR: /memory-add requires bullet text as argument."
  exit 1
fi

if [[ "$ARG" == *$'\n'* ]]; then
  echo "ERROR: /memory-add bullet must be a single line. Multi-line input is not allowed (one bullet per invocation)."
  exit 1
fi

mkdir -p ~/.claude/memory
printf -- '- %s\n' "$ARG" >> ~/.claude/memory/staging.md
echo "Staged to memory/staging.md for next weekly distill."
