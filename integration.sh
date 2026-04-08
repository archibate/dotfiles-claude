claude() {
    local _session
    _session="$(basename "$PWD")-$(openssl rand -hex 8 2>/dev/null || printf '%05x%05x' $RANDOM $RANDOM)"
    PYTHONUNBUFFERED=1 \
    AGENT_BROWSER_SESSION="$_session" \
    command claude "$@"
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

commit() {
    timeout -v -s INT 80s claude -p --model haiku --max-turns 50 \
        "Make a git commit with commit message briefly describing what changed in the codebase. Stage and commit all changed files (including untracked ones). If some stagable files looks like should appear in .gitignore, add the file name pattern to .gitignore before stage. Do not edit files in this conversation."
}
