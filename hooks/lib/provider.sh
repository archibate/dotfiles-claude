#!/usr/bin/bash
# Provider/runtime helpers shared by hooks.

is_official_anthropic_runtime() {
    local base="${ANTHROPIC_BASE_URL:-}"

    if [ -n "$base" ]; then
        local host="$base"
        host="${host#http://}"
        host="${host#https://}"
        host="${host%%/*}"
        host="${host%%:*}"
        [ "$host" = "api.anthropic.com" ] || return 1
    fi

    local model
    for model in \
        "${ANTHROPIC_DEFAULT_MODEL:-}" \
        "${ANTHROPIC_DEFAULT_HAIKU_MODEL:-}" \
        "${ANTHROPIC_DEFAULT_SONNET_MODEL:-}" \
        "${ANTHROPIC_DEFAULT_OPUS_MODEL:-}"
    do
        [ -n "$model" ] || continue
        case "$model" in
            claude-*|haiku|sonnet|opus|opusplan)
                ;;
            *)
                return 1
                ;;
        esac
    done

    return 0
}
