# Environment Variables Reference

Source: [code.claude.com/docs/en/env-vars](https://code.claude.com/docs/en/env-vars), v2.1.116. Comprehensive list. Headless/CI-relevant variables are marked 🎯 in the Notes column.

## Authentication & API

| Variable | Purpose | Values | Default |
|---|---|---|---|
| `ANTHROPIC_API_KEY` | API key for Anthropic API | API key string | None |
| `ANTHROPIC_AUTH_TOKEN` | Custom Authorization header (prefixed with `Bearer `) | String | None |
| `ANTHROPIC_BASE_URL` | Override API endpoint | URL | `https://api.anthropic.com` |
| `ANTHROPIC_BETAS` | Comma-separated beta header values | Comma-separated list | None |
| `ANTHROPIC_CUSTOM_HEADERS` | Custom request headers (`Name: Value` per line) | String | None |
| `ANTHROPIC_BEDROCK_BASE_URL` | Bedrock endpoint URL override | URL | None |
| `ANTHROPIC_BEDROCK_MANTLE_BASE_URL` | Bedrock Mantle endpoint URL override | URL | None |
| `ANTHROPIC_VERTEX_BASE_URL` | Vertex AI endpoint URL override | URL | None |
| `ANTHROPIC_VERTEX_PROJECT_ID` | GCP project ID for Vertex AI | String | Required for Vertex |
| `ANTHROPIC_FOUNDRY_API_KEY` | Microsoft Foundry API key | String | None |
| `ANTHROPIC_FOUNDRY_BASE_URL` | Foundry resource base URL | URL | None |
| `ANTHROPIC_FOUNDRY_RESOURCE` | Foundry resource name | String | None |
| `AWS_BEARER_TOKEN_BEDROCK` | Bedrock API key | String | None |
| `ANTHROPIC_OAUTH_TOKEN` | OAuth access token for Claude.ai | String | None |
| `CLAUDE_CODE_OAUTH_TOKEN` 🎯 | OAuth token (alternative form, used by `claude setup-token`) | String | None |
| `CLAUDE_CODE_OAUTH_REFRESH_TOKEN` | OAuth refresh token | String | None |
| `CLAUDE_CODE_OAUTH_SCOPES` | OAuth scopes for refresh token | Space-separated list | None |
| `CLAUDE_CODE_SKIP_BEDROCK_AUTH` | Skip AWS auth for Bedrock | `1` | unset |
| `CLAUDE_CODE_SKIP_VERTEX_AUTH` | Skip Google auth for Vertex | `1` | unset |
| `CLAUDE_CODE_SKIP_FOUNDRY_AUTH` | Skip Azure auth for Foundry | `1` | unset |
| `CLAUDE_CODE_SKIP_MANTLE_AUTH` | Skip AWS auth for Bedrock Mantle | `1` | unset |

## Model Selection

| Variable | Purpose | Values | Default |
|---|---|---|---|
| `ANTHROPIC_MODEL` | Model to use | Model name/ID | None |
| `ANTHROPIC_DEFAULT_OPUS_MODEL` | Opus-class model override | Model ID | None |
| `ANTHROPIC_DEFAULT_OPUS_MODEL_NAME` | Display name for custom Opus | String | Model ID |
| `ANTHROPIC_DEFAULT_OPUS_MODEL_DESCRIPTION` | Display description | String | None |
| `ANTHROPIC_DEFAULT_OPUS_MODEL_SUPPORTED_CAPABILITIES` | Capabilities | Comma-separated list | See model-config docs |
| `ANTHROPIC_DEFAULT_SONNET_MODEL` | Sonnet-class override | Model ID | None |
| `ANTHROPIC_DEFAULT_SONNET_MODEL_NAME` | Display name | String | Model ID |
| `ANTHROPIC_DEFAULT_SONNET_MODEL_DESCRIPTION` | Display description | String | None |
| `ANTHROPIC_DEFAULT_SONNET_MODEL_SUPPORTED_CAPABILITIES` | Capabilities | Comma-separated list | See model-config docs |
| `ANTHROPIC_DEFAULT_HAIKU_MODEL` | Haiku-class override | Model ID | None |
| `ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME` | Display name | String | Model ID |
| `ANTHROPIC_DEFAULT_HAIKU_MODEL_DESCRIPTION` | Display description | String | None |
| `ANTHROPIC_DEFAULT_HAIKU_MODEL_SUPPORTED_CAPABILITIES` | Capabilities | Comma-separated list | See model-config docs |
| `ANTHROPIC_CUSTOM_MODEL_OPTION` | Custom model ID in picker | Model ID | None |
| `ANTHROPIC_CUSTOM_MODEL_OPTION_NAME` | Display name | String | Model ID |
| `ANTHROPIC_CUSTOM_MODEL_OPTION_DESCRIPTION` | Display description | String | `Custom model (<model-id>)` |
| `ANTHROPIC_CUSTOM_MODEL_OPTION_SUPPORTED_CAPABILITIES` | Capabilities | Comma-separated list | None |
| `ANTHROPIC_SMALL_FAST_MODEL` | ⚠️ DEPRECATED — Haiku-class for background tasks | Model ID | None |
| `ANTHROPIC_SMALL_FAST_MODEL_AWS_REGION` | AWS region for Haiku model (Bedrock/Mantle) | AWS region | None |
| `CLAUDE_CODE_SUBAGENT_MODEL` | Model for subagents | Model ID | None |
| `CLAUDE_CODE_DISABLE_1M_CONTEXT` | Disable 1M context window | `1` | unset (enabled) |
| `CLAUDE_CODE_DISABLE_LEGACY_MODEL_REMAP` | Prevent automatic Opus 4.0/4.1 remapping | `1` | unset |

## Thinking & Reasoning

| Variable | Purpose | Values | Default |
|---|---|---|---|
| `CLAUDE_CODE_DISABLE_THINKING` | Force-disable extended thinking | `1` | unset |
| `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING` | Disable adaptive reasoning on Opus/Sonnet 4.6 | `1` | unset |
| `MAX_THINKING_TOKENS` | Fixed thinking budget | Integer (tokens) | Model default |
| `CLAUDE_CODE_EFFORT_LEVEL` | Effort level | `low\|medium\|high\|xhigh\|max\|auto` | Model default |

## Output & Token Limits

| Variable | Purpose | Values | Default |
|---|---|---|---|
| `CLAUDE_CODE_MAX_OUTPUT_TOKENS` | Maximum output tokens | Integer | Model default |
| `CLAUDE_CODE_FILE_READ_MAX_OUTPUT_TOKENS` | Max tokens for file reads | Integer | Internal default |
| `BASH_MAX_OUTPUT_LENGTH` | Max characters in bash outputs | Integer | Internal default |

## Tool & Feature Toggles

| Variable | Purpose | Values | Default |
|---|---|---|---|
| `CLAUDE_CODE_DISABLE_ATTACHMENTS` | Disable file attachment processing | `1` | unset |
| `CLAUDE_CODE_DISABLE_FILE_CHECKPOINTING` | Disable file checkpointing | `1` | unset |
| `CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS` | Remove git workflow instructions from prompt | `1` | unset |
| `CLAUDE_CODE_DISABLE_CRON` | Disable scheduled tasks | `1` | unset |
| `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS` | Disable background tasks | `1` | unset |
| `CLAUDE_CODE_AUTO_BACKGROUND_TASKS` | Force-enable auto-backgrounding | `1` | unset (auto) |
| `CLAUDE_CODE_DISABLE_FAST_MODE` | Disable fast mode | `1` | unset |
| `CLAUDE_CODE_DISABLE_AUTO_MEMORY` | Disable auto memory | `1` to disable, `0` to force on | unset (rollout-dependent) |
| `CLAUDE_CODE_DISABLE_CLAUDE_MDS` 🎯 | Prevent loading CLAUDE.md files | `1` | unset |
| `CLAUDE_CODE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD` | Load CLAUDE.md from `--add-dir` directories | `1` | unset |
| `CLAUDE_CODE_ENABLE_TASKS` 🎯 | Enable task tracking in `-p` mode | `1` | unset (off in `-p`) |
| `CLAUDE_CODE_ENABLE_AWAY_SUMMARY` | Override session recap availability | `0\|1` | unset |
| `CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION` | Enable prompt suggestions | `false` to disable | unset (enabled) |
| `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS` | Strip Anthropic beta headers | `1` | unset |

## Bash & Shell

| Variable | Purpose | Values | Default |
|---|---|---|---|
| `BASH_DEFAULT_TIMEOUT_MS` 🎯 | Default bash command timeout | Integer ms | 120000 (2 min) |
| `BASH_MAX_TIMEOUT_MS` 🎯 | Max timeout model can request | Integer ms | 600000 (10 min) |
| `CLAUDE_CODE_SHELL` | Override shell detection | `bash\|zsh\|...` | Auto-detected |
| `CLAUDE_CODE_SHELL_PREFIX` | Command prefix for bash | Command path | None |
| `CLAUDE_CODE_GIT_BASH_PATH` | Windows: Git Bash path | File path | Auto-detected |
| `CLAUDE_CODE_USE_POWERSHELL_TOOL` | Enable PowerShell tool | `0\|1` | Rolling out on Windows |
| `CLAUDE_CODE_BASH_MAINTAIN_PROJECT_WORKING_DIR` | Reset cwd between commands | `1` | unset |
| `CLAUDE_CODE_PERFORCE_MODE` | Perforce-aware write protection | `1` | unset |
| `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` 🎯 | Strip credentials from subprocess env | `1` | unset |
| `CLAUDE_CODE_SCRIPT_CAPS` | Per-script invocation cap | JSON object (e.g., `{"deploy.sh": 2}`) | None |
| `CLAUDE_CODE_PROXY_RESOLVES_HOSTS` | Allow proxy to do DNS resolution | `1` | unset |
| `CLAUDE_ENV_FILE` | Shell script to source before bash commands | File path | None |

## File & Glob

| Variable | Purpose | Values | Default |
|---|---|---|---|
| `CLAUDE_CODE_GLOB_HIDDEN` | Include dotfiles in Glob results | `false` to exclude | unset (included) |
| `CLAUDE_CODE_GLOB_NO_IGNORE` | Make Glob respect `.gitignore` | `false` to respect | unset (ignores `.gitignore`) |
| `CLAUDE_CODE_GLOB_TIMEOUT_SECONDS` | Glob tool timeout | Integer seconds | 20 (60 on WSL) |

## Context & Memory

| Variable | Purpose | Values | Default |
|---|---|---|---|
| `CLAUDE_CODE_MAX_CONTEXT_TOKENS` | Override context window size | Integer | Model default |
| `CLAUDE_CODE_AUTO_COMPACT_WINDOW` | Context capacity for auto-compaction | Integer | Model's context window |
| `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` | Auto-compact trigger percentage | 1-100 | ~95 |
| `DISABLE_COMPACT` | Disable auto-compaction | `1` | unset |

## Network & Timeouts

| Variable | Purpose | Values | Default |
|---|---|---|---|
| `API_TIMEOUT_MS` 🎯 | API request timeout | Integer ms (max 2147483647) | 600000 (10 min) |
| `CLAUDE_STREAM_IDLE_TIMEOUT_MS` | Streaming idle timeout | Integer ms | None |
| `CLAUDE_ENABLE_STREAM_WATCHDOG` | Event-level streaming watchdog | `0\|1` | Off |
| `CLAUDE_ENABLE_BYTE_WATCHDOG` | Byte-level streaming watchdog | `0\|1` | On for Anthropic API |

## IDE Integration

| Variable | Purpose | Values | Default |
|---|---|---|---|
| `CLAUDE_CODE_AUTO_CONNECT_IDE` | Override IDE auto-connect | `true\|false` | Auto-detect |
| `CLAUDE_CODE_IDE_HOST_OVERRIDE` | Override IDE host | Hostname/IP | Auto-detected |
| `CLAUDE_CODE_IDE_SKIP_AUTO_INSTALL` | Skip IDE extension auto-install | `1` | unset |
| `CLAUDE_CODE_IDE_SKIP_VALID_CHECK` | Skip IDE lockfile validation | `1` | unset |

## Plugins & Marketplace

| Variable | Purpose | Values | Default |
|---|---|---|---|
| `CLAUDE_CODE_PLUGIN_CACHE_DIR` | Override plugins root | File path | `~/.claude/plugins` |
| `CLAUDE_CODE_PLUGIN_GIT_TIMEOUT_MS` | Plugin git op timeout | Integer ms | 120000 |
| `CLAUDE_CODE_PLUGIN_KEEP_MARKETPLACE_ON_FAILURE` | Keep marketplace cache on git pull failure | `1` | unset |
| `CLAUDE_CODE_PLUGIN_SEED_DIR` | Read-only plugin seed directories | `:`-sep (Unix) / `;`-sep (Windows) | None |
| `CLAUDE_CODE_DISABLE_OFFICIAL_MARKETPLACE_AUTOINSTALL` 🎯 | Skip official marketplace on first run | `1` | unset |
| `CLAUDE_CODE_SYNC_PLUGIN_INSTALL` | Wait for plugin install before first query | `1` | unset (background) |
| `CLAUDE_CODE_SYNC_PLUGIN_INSTALL_TIMEOUT_MS` | Sync plugin install timeout | Integer ms | No limit |
| `CLAUDE_CODE_ENABLE_BACKGROUND_PLUGIN_REFRESH` | Refresh plugins at turn boundaries | `1` | unset |

## MCP

| Variable | Purpose | Values | Default |
|---|---|---|---|
| `CLAUDE_AGENT_SDK_MCP_NO_PREFIX` | Skip `mcp__<server>__` prefix on tool names | `1` | unset |
| `ENABLE_TOOL_SEARCH` | Enable MCP tool search with custom base URL | `true` | Disabled for non-first-party hosts |

## Telemetry & Reporting

| Variable | Purpose | Values | Default |
|---|---|---|---|
| `DISABLE_TELEMETRY` 🎯 | Disable telemetry | `1` | unset |
| `DISABLE_AUTOUPDATER` 🎯 | Disable auto-update checking | `1` | unset |
| `DISABLE_ERROR_REPORTING` 🎯 | Disable error reporting | `1` | unset |
| `DISABLE_FEEDBACK_COMMAND` | Disable feedback command | `1` | unset |
| `CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY` | Disable session quality surveys | `1` | unset |
| `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` 🎯 | Disable all of the above in one switch | `1` | unset |
| `CLAUDE_CODE_ENABLE_TELEMETRY` | Enable OpenTelemetry data collection | `1` | unset |
| `CLAUDE_CODE_OTEL_FLUSH_TIMEOUT_MS` | OTel flush timeout | Integer ms | 5000 |
| `CLAUDE_CODE_OTEL_SHUTDOWN_TIMEOUT_MS` | OTel exporter shutdown timeout | Integer ms | 2000 |
| `CLAUDE_CODE_OTEL_HEADERS_HELPER_DEBOUNCE_MS` | OTel headers refresh interval | Integer ms | 1740000 (29 min) |

## UI & Display

(Mostly interactive-only; included for completeness.)

| Variable | Purpose | Values | Default |
|---|---|---|---|
| `CLAUDE_CODE_NO_FLICKER` | Fullscreen rendering (research preview) | `1` | unset |
| `CLAUDE_CODE_DISABLE_MOUSE` | Disable mouse tracking in fullscreen | `1` | unset |
| `CLAUDE_CODE_DISABLE_VIRTUAL_SCROLL` | Disable virtual scrolling | `1` | unset |
| `CLAUDE_CODE_SCROLL_SPEED` | Mouse wheel scroll multiplier | 1-20 | Internal default |
| `CLAUDE_CODE_DISABLE_TERMINAL_TITLE` | Disable terminal title updates | `1` | unset |
| `CLAUDE_CODE_CODE_ACCESSIBILITY` | Keep native cursor visible | `1` | unset |
| `CLAUDE_CODE_TMUX_TRUECOLOR` | 24-bit truecolor in tmux | `1` | unset (256 colors in tmux) |
| `CLAUDE_CODE_SYNTAX_HIGHLIGHT` | Syntax highlighting in diffs | `false` to disable | unset (enabled) |

## Logging & Debugging

| Variable | Purpose | Values | Default |
|---|---|---|---|
| `CLAUDE_CODE_DEBUG_LOGS_DIR` 🎯 | Override debug log file path | File path | `~/.claude/debug/<session-id>.txt` |
| `CLAUDE_CODE_DEBUG_LOG_LEVEL` | Minimum log level | `verbose\|debug\|info\|warn\|error` | `debug` |

## Session & Workflow

| Variable | Purpose | Values | Default |
|---|---|---|---|
| `CLAUDE_CODE_SKIP_PROMPT_HISTORY` 🎯 | Skip writing prompt history to disk | `1` | unset |
| `CLAUDE_CODE_RESUME_INTERRUPTED_TURN` | Auto-resume mid-turn sessions | `1` | unset |
| `CLAUDE_CODE_EXIT_AFTER_STOP_DELAY` | Delay before auto-exit | Integer ms | None |
| `CLAUDE_CODE_TASK_LIST_ID` | Shared task list ID across sessions | String | None |
| `CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS` | SessionEnd hooks time budget | Integer ms | 1500 (auto-raised up to 60000) |

## Directory & Path

| Variable | Purpose | Values | Default |
|---|---|---|---|
| `CLAUDE_CONFIG_DIR` 🎯 | Override config directory | File path | `~/.claude` |
| `CLAUDE_CODE_TMPDIR` | Override temp directory | File path | `/tmp` (macOS), `os.tmpdir()` (Linux/Windows) |

## TLS & Certificates

| Variable | Purpose | Values | Default |
|---|---|---|---|
| `CLAUDE_CODE_CERT_STORE` | CA cert sources | Comma-separated `bundled,system` | `bundled,system` |
| `CLAUDE_CODE_CLIENT_CERT` | mTLS client certificate | File path | None |
| `CLAUDE_CODE_CLIENT_KEY` | mTLS client private key | File path | None |
| `CLAUDE_CODE_CLIENT_KEY_PASSPHRASE` | Passphrase for encrypted key | String | None |

## Environment Detection

(Set by Claude Code itself — read by hooks, statuslines, agents.)

| Variable | Purpose | Values | Default |
|---|---|---|---|
| `CLAUDECODE` | Detect Claude Code shell environment | `1` in spawned shells | unset in hooks/statusline |
| `CLAUDE_CODE_REMOTE` | Detect cloud session | `true` in cloud | unset locally |
| `CLAUDE_CODE_REMOTE_SESSION_ID` | Cloud session ID | String | Set automatically in cloud |
| `CLAUDE_CODE_TEAM_NAME` | Agent team membership | String | unset |
| `CLAUDE_CODE_SIMPLE` 🎯 | Run with minimal system prompt (set by `--bare`) | `1` | unset |
| `CLAUDE_AGENT_SDK_DISABLE_BUILTIN_AGENTS` | Disable built-in subagent types | `1` | unset (non-interactive only) |
| `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` | Enable agent teams (experimental) | `1` | unset |

## Remote & Cloud

| Variable | Purpose | Values | Default |
|---|---|---|---|
| `CCR_FORCE_BUNDLE` | Force repo bundling for remote mode | `1` | unset |

## Misc / Advanced

| Variable | Purpose | Values | Default |
|---|---|---|---|
| `CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY` | Max parallel read-only tools/subagents | Integer | 10 |
| `CLAUDE_CODE_MAX_RETRIES` 🎯 | API request retry attempts | Integer | 10 |
| `CLAUDE_CODE_NEW_INIT` | Run `/init` with interactive setup | `1` | unset |
| `CLAUDE_CODE_API_KEY_HELPER_TTL_MS` | Credential refresh interval (apiKeyHelper) | Integer ms | None |
| `CLAUDE_CODE_ENABLE_FINE_GRAINED_TOOL_STREAMING` | Force fine-grained tool input streaming | `1` | unset |
| `CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK` | Disable non-streaming fallback on error | `1` | unset |

## Common CI Snippet

```bash
# Quiet, isolated, deterministic CI run. Auth via ANTHROPIC_API_KEY or apiKeyHelper — see auth.md.
export ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY_SECRET"
export CLAUDE_CONFIG_DIR=/tmp/claude-ci-config
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
export CLAUDE_CODE_SKIP_PROMPT_HISTORY=1
export CLAUDE_CODE_DISABLE_OFFICIAL_MARKETPLACE_AUTOINSTALL=1
export API_TIMEOUT_MS=900000
export BASH_MAX_TIMEOUT_MS=1800000

claude --bare -p "$TASK" --output-format json --max-budget-usd 2.00
```
