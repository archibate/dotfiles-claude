# Provider shortcuts. Source this *after* integration.sh if you have one or
# more of the corresponding API keys set in your environment:
#   ZAI_API_KEY        → glm     (Zhipu BigModel)
#   DEEPSEEK_API_KEY   → deepseek
#   OPENROUTER_API_KEY → openrouter
#   LLAMA_API_KEY      → qwen
#   (none)             → gpt     (ChatGPT OAuth — needs the codex-to-claude
#                                 proxy running locally; see
#                                 https://github.com/archibate/codex-to-claude)
#
# Each shortcut routes claude through ~/.claude/providers/<name>.json which
# rebinds ANTHROPIC_BASE_URL and the haiku/sonnet/opus model aliases to the
# provider's catalog.

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
        openrouter)
            token="$OPENROUTER_API_KEY"
            ;;
        qwen)
            token="$LLAMA_API_KEY"
            ;;
        gpt)
            # codex-to-claude proxy: ChatGPT OAuth backend, no real token needed.
            token="dummy"
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

openrouter() {
    claude-with openrouter "$@"
}

qwen() {
    claude-with qwen "$@"
}

gpt() {
    claude-with gpt "$@"
}
