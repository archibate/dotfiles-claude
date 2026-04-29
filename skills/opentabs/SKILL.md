---
name: opentabs
description: Call real web APIs (Slack, Discord, GitHub, Jira, Notion, Figma, AWS, Stripe, and 100+ more) through the user's authenticated browser session via the local OpenTabs MCP server. Also exposes built-in browser tools (screenshots, click, type, network capture) on any open tab. TRIGGER when the user asks to interact with a logged-in web service without API keys, automate a SaaS task using their existing session, or take browser actions on a real tab.
allowed-tools:
  - Bash(*mcpcall.py*:*)
  - Bash(opentabs:*)
---

# OpenTabs

Local MCP server that proxies authenticated web API calls through the user's browser session. No API keys required — if the user is logged in to the site in Chrome, OpenTabs can hit the site's APIs as them.

This skill wraps the **Gateway MCP** endpoint (`/mcp/gateway`), which exposes 2 meta-tools that dynamically discover and invoke any installed plugin tool. Keeps context cost flat regardless of how many plugins are enabled.

## Prerequisites

1. **Server running**: `opentabs status` should show the server up. If not: `opentabs start --background`.
2. **Chrome extension loaded**: from `~/.opentabs/extension` via `chrome://extensions/` (Developer mode → Load unpacked). Without it, no plugin tools work and built-in browser tools have nothing to talk to.
3. **Tools enabled**: every tool starts as `[Disabled]`. The user must approve tools per-plugin in the extension UI, or set permissions via `opentabs plugin perm <plugin> <tool> <off|ask|auto>`.

## Auth

Auto-discovered via `opentabs config show --json --show-secret`. Override by setting `OPENTABS_TOKEN`.

## opentabs_list_tools

Discover available tools, optionally filtered by plugin. Returns a JSON array of `{name, description, inputSchema, plugin}`. Tools prefixed `[Disabled]` in their description need to be enabled before use.

- `plugin` (optional): filter by plugin name (e.g. `"slack"`, `"browser"`, `"github"`)

```bash
scripts/mcpcall.py opentabs_list_tools
scripts/mcpcall.py opentabs_list_tools plugin:browser
```

## opentabs_call

Invoke any tool by name. Pass `tool` (the tool name) and `arguments` (an object matching that tool's `inputSchema`).

- `tool` (required): tool name as returned by `opentabs_list_tools` (e.g. `"browser_list_tabs"`, `"slack_send_message"`)
- `arguments` (optional): object of tool-specific parameters

Always pass via `--args` (JSON), since the `arguments` field is a nested object:

```bash
scripts/mcpcall.py opentabs_call --args '{"tool": "browser_list_tabs", "arguments": {}}'
scripts/mcpcall.py opentabs_call --args '{"tool": "browser_open_tab", "arguments": {"url": "https://example.com"}}'
scripts/mcpcall.py opentabs_call --args '{"tool": "slack_send_message", "arguments": {"channel": "C123", "text": "hi"}}'
```

## Typical Workflow

1. List relevant tools: `mcpcall.py opentabs_list_tools plugin:<name>`
2. Read the `inputSchema` of the tool you want
3. Call it: `mcpcall.py opentabs_call --args '{"tool": "<name>", "arguments": {...}}'`

## Plugin Management (CLI)

Plugin install/list/permissions are managed by the `opentabs` CLI, not the MCP gateway:

```bash
opentabs plugin list                  # see installed plugins
opentabs plugin install <name>        # install a plugin from npm
opentabs plugin perm <plugin> <tool> <off|ask|auto>   # set permission
opentabs status                       # server + connected plugins
opentabs audit                        # recent tool invocations
```

Built-in browser plugin (`browser_*` tools) is always present once the Chrome extension is connected.

## Gotchas

- **`[Disabled]` prefix**: tool descriptions starting with `[Disabled]` will refuse to execute. Enable via the extension UI or `opentabs plugin perm`.
- **Browser tools need a connected extension**: `browser_list_tabs` returns empty if Chrome isn't running with the extension loaded.
- **Sensitive tabs**: `browser_list_tabs` returns *all* open tabs including banking/email. Don't pipe tab URLs into plugin calls without user intent.
- **Permissions reset on plugin update**: when a plugin upgrades, its previously-approved tools revert to `off` until re-approved.
