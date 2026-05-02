function claude
    set -lx SHELL (command -v bash)
    set -lx PYTHONUNBUFFERED 1
    set -lx AGENT_BROWSER_SESSION (basename $PWD)-(command -sq openssl; and openssl rand -hex 8; or random)
    command claude --thinking-display summarized --allow-dangerously-skip-permissions $argv
end

function claude-simple
    set -lx CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT 1
    if test (count $argv) -eq 0
        claude
    else
        $argv
    end
end

function opus
    claude --model opus $argv
end

function opusplan
    claude --model opusplan --permission-mode plan $argv
end

function sonnet
    claude --model sonnet $argv
end

function haiku
    claude --model haiku $argv
end

function commit
    set -l extra ""
    if set -q argv[1]
        set extra " Additional user note to help you understand: $argv"
    end
    timeout -v -s INT 80s claude -p --model haiku --max-turns 50 \
        "Make a git commit with commit message briefly describing what changed in the codebase. Stage and commit all changed files (including untracked ones). If some stagable files looks like should appear in .gitignore, add the file name pattern to .gitignore before stage. Do not edit files in this conversation.$extra"
end
