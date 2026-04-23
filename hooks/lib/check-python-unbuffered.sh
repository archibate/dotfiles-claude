#!/usr/bin/bash
# Shared helper: check if a command invokes python (directly or via just)
# and whether PYTHONUNBUFFERED/​-u is set.
#
# Usage: source this file, then call:
#   check_python_unbuffered "$command" "$cwd"
#
# Returns:
#   0 = python found AND not unbuffered (needs fix)
#   1 = no python, or already unbuffered (OK)

check_python_unbuffered() {
    local command="$1"
    local cwd="${2:-.}"

    # Already unbuffered via inherited environment (Python treats any non-empty value as truthy)
    if [ -n "${PYTHONUNBUFFERED:-}" ]; then
        return 1  # OK
    fi

    local has_python=false
    local recipe=""

    # Direct python invocation
    if echo "$command" | grep -qP '\b(python3?|uv\s+run)\b'; then
        has_python=true
    fi

    # Just invocation: resolve recipe to check for python
    if echo "$command" | grep -qP '\bjust\b'; then
        # Extract targets: words after 'just' that don't start with -
        local targets
        targets=$(echo "$command" | sed 's/.*\bjust\b//' | tr -s ' ' '\n' | grep -v '^\s*$' | grep -v '^-' | head -5)

        if [ -z "$targets" ]; then
            # No explicit target = default recipe
            targets="_default"
        fi

        for target in $targets; do
            local r
            r=$(cd "$cwd" && just --show "$target" 2>/dev/null || true)
            if [ -n "$r" ]; then
                recipe="${recipe}${r}"$'\n'
                if echo "$r" | grep -qP '\b(python3?|uv\s+run)\b'; then
                    has_python=true
                fi
            fi
        done
    fi

    if ! $has_python; then
        return 1  # No python found, OK
    fi

    # Check if PYTHONUNBUFFERED is set in command or recipe
    if echo "$command" | grep -qF 'PYTHONUNBUFFERED'; then
        return 1  # OK
    fi
    if [ -n "$recipe" ] && echo "$recipe" | grep -qF 'PYTHONUNBUFFERED'; then
        return 1  # OK
    fi

    # Check if python -u is used in command or recipe
    if echo "$command" | grep -qP '\bpython3?\s+-u\b'; then
        return 1  # OK
    fi
    if [ -n "$recipe" ] && echo "$recipe" | grep -qP '\bpython3?\s+-u\b'; then
        return 1  # OK
    fi

    return 0  # Python found, not unbuffered — needs fix
}
