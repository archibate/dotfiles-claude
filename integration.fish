if not contains $HOME/.claude/bin $PATH
    set -gx PATH $HOME/.claude/bin $PATH
end

function claude
    set -lx SHELL (command -v bash)
    set -lx PYTHONUNBUFFERED 1
    set -lx AGENT_BROWSER_SESSION (basename $PWD)-(command -sq openssl; and openssl rand -hex 8; or random)
    command claude --thinking-display summarized --allow-dangerously-skip-permissions $argv
end

function ultraclaude
    claude --model 'opus[1m]' --effort max --settings '{"disableWorkflows": false, "effort": "ultracode"}'
end

function fable
    claude --model 'claude-fable-5' $argv
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

function fuck
    claude $history[1] $argv
end

function commit
    set -l extra ""
    if set -q argv[1]
        set extra " Additional user note to help you understand: $argv"
    end
    set -lx CLAUDE_CODE_DISABLE_POLICY_SKILLS 1
    set -lx CLAUDE_CODE_DISABLE_AUTO_MEMORY 1
    set -lx ENABLE_CLAUDEAI_MCP_SERVERS false
    set -lx CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC 1
    set -lx AUDIT_BACKEND none
    timeout -v -s INT 80s claude -p --model haiku --max-turns 50 \
        "Make a git commit with commit message briefly describing what changed in the codebase. Stage and commit all changed files (including untracked ones). If some stagable files looks like should appear in .gitignore, add the file name pattern to .gitignore before stage. Do not edit files in this conversation.$extra"
    if command -sq gitleaks; and not gitleaks detect --no-banner
        echo "WARNING: gitleaks detected secrets" >&2
    end
end
