claude() {
    local _session
    _session="$(basename "$PWD")-$(openssl rand -hex 8 2>/dev/null || printf '%05x%05x' $RANDOM $RANDOM)"
    SHELL="$(command -v bash)" \
    PYTHONUNBUFFERED=1 \
    AGENT_BROWSER_SESSION="$_session" \
    command claude --thinking-display summarized --allow-dangerously-skip-permissions "$@"
}

claude-simple() {
    if [ $# -eq 0 ]; then
        CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT=1 claude
    else
        CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT=1 "$@"
    fi
}

claude-bare() {
    command claude --bare --settings ~/.claude/bare-settings.json "$@"
}

opus() {
    claude --model opus "$@"
}

opusplan() {
    claude --model opusplan --permission-mode plan "$@"
}

sonnet() {
    claude --model sonnet "$@"
}

haiku() {
    claude --model haiku "$@"
}

claude-with() {
    local provider="$1"
    shift
    local token
    case "$provider" in
        glm)
            token="$ZAI_API_KEY"
            ;;
        deepseek)
            token="$DEEPSEEK_API_KEY"
            ;;
        aigcdesk)
            token="$AIGCDESK_API_KEY"
            ;;
        openrouter)
            token="$OPENROUTER_API_KEY"
            ;;
        evolink)
            token="$EVOLINK_API_KEY"
            ;;
        qwen)
            token="$LLAMA_API_KEY"
            ;;
        *)
            echo "claude-with: unknown provider '$provider'" >&2
            return 1
            ;;
    esac
    ANTHROPIC_AUTH_TOKEN="$token" claude --settings ~/.claude/providers/"$provider".json "$@"
}

glm() {
    claude-with glm "$@"
}

deepseek() {
    claude-with deepseek "$@"
}

aigcdesk() {
    claude-with aigcdesk "$@"
}

openrouter() {
    claude-with openrouter "$@"
}

evolink() {
    claude-with evolink "$@"
}

qwen() {
    claude-with qwen "$@"
}

commit() {
    local extra=""
    if [ $# -gt 0 ]; then
        extra=" Additional user note to help you understand: $*"
    fi
    timeout -v -s INT 80s claude -p --model haiku --max-turns 50 \
        "Make a git commit with commit message briefly describing what changed in the codebase. Stage and commit all changed files (including untracked ones). If some stagable files looks like should appear in .gitignore, add the file name pattern to .gitignore before stage. Do not edit files in this conversation.${extra}"
}
