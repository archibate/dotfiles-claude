#!/usr/bin/env bash
# Interactive helper that wires the shell-integration source line into the
# user's rc file. Idempotent — re-running adds nothing if the line already
# exists. Run on demand: `bash ~/.claude/integration-install.sh`.
set -euo pipefail

if [ -t 1 ] && [ -t 2 ]; then
    BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
    GREEN=$'\033[32m'; YELLOW=$'\033[33m'; CYAN=$'\033[36m'; RED=$'\033[31m'
else
    BOLD=""; DIM=""; RESET=""; GREEN=""; YELLOW=""; CYAN=""; RED=""
fi

# Pick the most plausible shell. Prefer the user's $SHELL (login shell);
# fall back to the parent process when $SHELL is unset (rare).
detect_shell() {
    local s
    s=$(basename "${SHELL:-}" 2>/dev/null || true)
    case "$s" in
        bash|zsh|fish) echo "$s"; return ;;
    esac
    s=$(ps -p "$PPID" -o comm= 2>/dev/null | tr -d ' ' || true)
    case "$s" in
        bash|zsh|fish) echo "$s"; return ;;
    esac
    echo "unknown"
}

shell_name=$(detect_shell)
case "$shell_name" in
    bash)
        rc="$HOME/.bashrc"
        line="source ~/.claude/integration.sh"
        provider_line="source ~/.claude/integration-providers.sh"
        ;;
    zsh)
        rc="$HOME/.zshrc"
        line="source ~/.claude/integration.sh"
        provider_line="source ~/.claude/integration-providers.sh"
        ;;
    fish)
        rc="$HOME/.config/fish/config.fish"
        line="source ~/.claude/integration.fish"
        provider_line="source ~/.claude/integration-providers.fish"
        ;;
    *)
        echo "${RED}Could not detect bash/zsh/fish (\$SHELL=${SHELL:-unset}). Edit your rc file by hand.${RESET}" >&2
        exit 1
        ;;
esac

echo "${BOLD}Detected shell:${RESET} ${CYAN}${shell_name}${RESET}  ${DIM}(${rc})${RESET}"
echo

ensure_line() {
    local target="$1" want="$2" label="$3"
    mkdir -p "$(dirname "$target")"
    [ -f "$target" ] || touch "$target"
    if grep -qxF "$want" "$target"; then
        echo "  ${GREEN}✓${RESET} ${label} already present in ${target}"
        return
    fi
    printf '\n%s\n' "$want" >> "$target"
    echo "  ${GREEN}✓${RESET} appended ${label} to ${target}"
}

read -r -p "Add core integration to ${rc}? [Y/n] " ans
case "${ans:-y}" in
    y|Y|yes|YES) ensure_line "$rc" "$line" "core integration" ;;
    *)           echo "  ${YELLOW}skipped core integration${RESET}" ;;
esac

read -r -p "Add provider shortcuts (glm/deepseek/qwen/openrouter/gpt)? [y/N] " ans
case "${ans:-n}" in
    y|Y|yes|YES) ensure_line "$rc" "$provider_line" "provider shortcuts" ;;
    *)           echo "  ${YELLOW}skipped provider shortcuts${RESET}" ;;
esac

echo
echo "${GREEN}${BOLD}Done.${RESET} Open a new shell or run ${CYAN}source ${rc}${RESET} to load the changes."
