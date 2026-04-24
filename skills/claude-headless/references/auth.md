# Authentication Reference

Claude Code accepts credentials via two modes: normal (auto-discovery) and `--bare` (explicit-only). Cloud providers (Bedrock / Vertex / Foundry) use their own credentials in both modes.

## Standard Layout

Convention for `--bare` subscription auth:

| Path | Contents |
|---|---|
| `~/.claude/oat-token` | OAuth token from `claude setup-token`, mode 600 |
| `~/.claude/bare-settings.json` | `{"apiKeyHelper": "sh -c 'cat ~/.claude/oat-token'"}` |

Usage:

```bash
claude --bare --settings ~/.claude/bare-settings.json -p "QUERY"
```

## Getting a Credential

**Subscription OAuth** — Claude.ai Pro/Max quota. Two flows:

- `claude auth login` (or `/login` inside a session) — browser OAuth, saves to `~/.claude/.credentials.json`. Typical workstation setup.
- `claude setup-token` — prints a long-lived OAuth token to stdout, exits. Does not save — capture it yourself. Typical for scripts/CI.

**Anthropic API key** — metered API billing. Generate at [console.anthropic.com](https://console.anthropic.com).

## Normal Mode

Any of these are read automatically:

- `~/.claude/.credentials.json` — populated by `claude auth login`
- `CLAUDE_CODE_OAUTH_TOKEN` env var
- `ANTHROPIC_API_KEY` env var
- OS keychain
- `apiKeyHelper` command from settings

For workers that outlive the OAuth access token's expiry, also set `CLAUDE_CODE_OAUTH_REFRESH_TOKEN` and `CLAUDE_CODE_OAUTH_SCOPES`.

## --bare Mode

Two paths:

**API key:**

```bash
export ANTHROPIC_API_KEY="sk-ant-api03-..."
claude --bare -p "..."
```

**apiKeyHelper via `--settings`** — also the path for subscription OAuth tokens:

```json
// bare-settings.json
{ "apiKeyHelper": "cat /path/to/oat-token" }
```

```bash
claude --bare --settings bare-settings.json -p "..."
```

`CLAUDE_CODE_API_KEY_HELPER_TTL_MS` controls refresh interval.

## Cloud Providers

| Provider | Credential |
|---|---|
| AWS Bedrock | `AWS_BEARER_TOKEN_BEDROCK` or AWS SDK creds |
| Google Vertex AI | `ANTHROPIC_VERTEX_PROJECT_ID` + gcloud auth |
| Microsoft Foundry | `ANTHROPIC_FOUNDRY_API_KEY` |

Full variable list: `env-vars.md` → "Authentication & API".

## Token Storage Conventions

Claude Code does not look at any particular file for the setup-token output. Common patterns, most to least secure:

| Storage | Retrieval | Notes |
|---|---|---|
| System keyring (`secret-tool`, `pass`) | `apiKeyHelper: "secret-tool lookup ..."` | Encrypted at rest |
| GPG-encrypted file | `apiKeyHelper: "gpg -d ~/.claude/oat.gpg"` | Portable |
| Mode-600 plain file | `cat /path/to/token` | Relies on filesystem permissions |
| CI secret | Injected into job env | Standard for CI/CD |
| Shell rc (`export` in `.bashrc` / `config.fish`) | Automatic | Leaks into every child process |
