#!/usr/bin/env bash
set -euo pipefail

REPO="https://github.com/archibate/dotfiles-claude.git"
TARGET="$HOME/.claude"

# ANSI colors — only when stderr/stdout is a real terminal, otherwise leave
# the output clean for logs and pipes.
if [ -t 1 ] && [ -t 2 ]; then
    BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
    RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'
    BLUE=$'\033[34m'; CYAN=$'\033[36m'
else
    BOLD=""; DIM=""; RESET=""
    RED=""; GREEN=""; YELLOW=""; BLUE=""; CYAN=""
fi

# Hard dependencies. `claude` runs the harness this whole config targets;
# `git` clones/updates this repo below; `jq` parses every PreToolUse/PostToolUse
# hook payload; `uv` runs audit-edits.py (Stop hook + PreToolUse Write/Edit/
# MultiEdit); `node` runs the codex plugin's lifecycle/stop hooks; `npx`
# launches one-shot skill helpers like `npx defuddle`, `npx -y mcporter`,
# `npx skills`, `npx agent-browser`. Without these, install fails or hooks
# error on every tool call.
missing=()
for dep in claude git jq uv node npx; do
    command -v "$dep" >/dev/null 2>&1 || missing+=("$dep")
done
if [ "${#missing[@]}" -gt 0 ]; then
    echo "${RED}${BOLD}✗ Required dependencies not installed:${RESET} ${RED}${missing[*]}${RESET}" >&2
    echo "${YELLOW}${BOLD}Install hints:${RESET}" >&2
    echo "  ${CYAN}claude${RESET} → ${DIM}curl -fsSL https://claude.ai/install.sh | bash${RESET}" >&2
    echo "  ${CYAN}git${RESET}    → ${DIM}https://git-scm.com/downloads${RESET}  (apt/brew/pacman install git)" >&2
    echo "  ${CYAN}jq${RESET}     → ${DIM}https://jqlang.org/download/${RESET}  (apt/brew/pacman install jq)" >&2
    echo "  ${CYAN}uv${RESET}     → ${DIM}https://docs.astral.sh/uv/getting-started/installation/${RESET}" >&2
    echo "  ${CYAN}node${RESET}   → ${DIM}https://nodejs.org/${RESET}  (apt/brew/pacman install nodejs)" >&2
    echo "  ${CYAN}npx${RESET}    → ${DIM}ships with npm (apt/brew/pacman install npm)${RESET}" >&2
    if command -v claude >/dev/null 2>&1; then
        echo >&2
        echo "${YELLOW}Or let claude CLI handle the rest:${RESET}" >&2
        echo "  ${CYAN}claude \"install these tools on my system: ${missing[*]}\"${RESET}" >&2
    fi
    exit 1
fi

if [ -d "$TARGET/.git" ]; then
    # Refuse to pull when the existing checkout points at a different repo.
    # Exact-match the canonical github.com URL forms (HTTPS, SSH, ssh://),
    # with or without the .git suffix. Anything else — fork on another host,
    # mirror, similarly-named repo — is rejected so the install never
    # silently pulls from a remote it doesn't manage.
    current_remote=$(git -C "$TARGET" remote get-url origin 2>/dev/null || true)
    case "$current_remote" in
        https://github.com/archibate/dotfiles-claude|\
        https://github.com/archibate/dotfiles-claude.git|\
        git@github.com:archibate/dotfiles-claude|\
        git@github.com:archibate/dotfiles-claude.git|\
        ssh://git@github.com/archibate/dotfiles-claude|\
        ssh://git@github.com/archibate/dotfiles-claude.git)
            ;;
        *)
            echo "${RED}${BOLD}✗ ${TARGET} is already a git checkout, but 'origin' is:${RESET}" >&2
            echo "    ${current_remote:-<unset>}" >&2
            echo "${YELLOW}This installer manages ${REPO}.${RESET}" >&2
            echo "${YELLOW}Either back up ${TARGET} and re-run, or repoint origin:${RESET}" >&2
            echo "  ${CYAN}git -C ${TARGET} remote set-url origin ${REPO}${RESET}" >&2
            exit 1
            ;;
    esac
    echo "${BLUE}↻ Updating existing checkout at ${TARGET}…${RESET}"
    git -C "$TARGET" pull --ff-only
elif [ -d "$TARGET" ]; then
    # Existing non-git directory — typically a vanilla Claude Code install
    # carrying credentials, sessions, plugins, and edited settings. The
    # previous `git checkout -f -B main` here clobbered all of that. Back
    # it up to a timestamped sibling, clone fresh, then restore everything
    # the fresh clone doesn't already ship (i.e. all gitignored runtime
    # state — sessions, credentials, history, installed plugins, etc.).
    # Locally-edited copies of tracked files (e.g. settings.json tweaks)
    # are NOT restored; they remain in the backup for the user to merge.
    backup="${TARGET}.bak.$(date +%Y%m%d-%H%M%S)"
    echo "${YELLOW}↻ Existing ${TARGET} found (no git checkout).${RESET}"
    echo "${YELLOW}  Moving to ${backup} and cloning fresh; runtime state will be restored.${RESET}"
    mv "$TARGET" "$backup"
    git clone "$REPO" "$TARGET"
    if command -v rsync >/dev/null 2>&1; then
        rsync -a --ignore-existing "$backup/" "$TARGET/"
    else
        cp -an "$backup/." "$TARGET/"
    fi
    echo "${GREEN}  ✓ runtime state restored; original preserved at ${backup}${RESET}"
else
    echo "${BLUE}↻ Cloning ${REPO} → ${TARGET}…${RESET}"
    git clone "$REPO" "$TARGET"
fi

# Install plugins declared as enabled in settings.json. `enabledPlugins: true`
# only flips the on/off bit for already-installed plugins — it never triggers
# a download. So on a fresh machine we have to issue `claude plugin install`
# explicitly for each one.
SETTINGS="$TARGET/settings.json"
if [ -f "$SETTINGS" ]; then
    installed_json="$TARGET/plugins/installed_plugins.json"
    if [ -f "$installed_json" ]; then
        installed=$(jq -r '.plugins | keys[]' "$installed_json" 2>/dev/null || true)
    else
        installed=""
    fi

    enabled=$(jq -r '.enabledPlugins // {} | to_entries[] | select(.value == true) | .key' "$SETTINGS")
    to_install=()
    while IFS= read -r p; do
        [ -z "$p" ] && continue
        if ! grep -qxF "$p" <<< "$installed"; then
            to_install+=("$p")
        fi
    done <<< "$enabled"

    if [ "${#to_install[@]}" -gt 0 ]; then
        echo
        echo "${BLUE}${BOLD}Installing ${#to_install[@]} plugin(s) declared in settings.json…${RESET}"
        for p in "${to_install[@]}"; do
            echo "  ${CYAN}↻ ${p}${RESET}"
            if ! claude plugin install "$p"; then
                echo "    ${YELLOW}⚠ failed; continuing${RESET}" >&2
            fi
        done
    fi
fi

echo
echo "${GREEN}${BOLD}✓ Setup complete.${RESET} ${DIM}(re-run this script anytime to pull updates)${RESET}"
echo
echo "${YELLOW}${BOLD}Optional next steps:${RESET}"
echo "  ${CYAN}bash ~/.claude/integration-install.sh${RESET}  ${DIM}— wire the shell integration into your rc file${RESET}"
echo "  ${CYAN}claude \"which CLI tools in ~/.claude/CLAUDE.md am I missing?\"${RESET}  ${DIM}— inventory preferred CLI tools${RESET}"
if ! command -v codex >/dev/null 2>&1; then
    echo "  ${CYAN}npm install -g @openai/codex${RESET}  ${DIM}— optional co-op: enables /codex:rescue, /codex:review, and the stop-time review gate${RESET}"
elif ! codex login status >/dev/null 2>&1; then
    echo "  ${CYAN}codex login${RESET}  ${DIM}— optional co-op: codex CLI is installed but not authed${RESET}"
fi
