---
name: mcpcall
description: >
  Guide and template for converting MCP servers into self-contained Claude Code skills
  with a Python wrapper script. This skill should be used before creating a new MCP-backed
  skill or wrapping an MCP server as a self-contained Claude Code skill.
---

# mcpcall

Convert any MCP server into a self-contained Claude Code skill with a Python wrapper in `scripts/mcpcall.py`.

Each MCP skill bundles its own `scripts/mcpcall.py` with the server URL baked in. No shared dependency, no cross-skill references — fully portable. Uses `httpx` (respects `http_proxy`/`https_proxy`) and MCP Streamable HTTP transport. Dependencies resolved by `uv` on first run via PEP 723 inline metadata.

The script is executable (`chmod +x`) with a `#!/usr/bin/env -S uv run --script` shebang, so it can be called directly without any prefix.

## Quick Start

1. Create skill directory with `scripts/` subfolder
2. Copy the appropriate template into `scripts/mcpcall.py`:
   - **No auth needed** → `references/template-noauth.py`
   - **API key required** → `references/template-auth.py`
3. `chmod +x scripts/mcpcall.py`
4. Edit the constants at the top of the script
5. Discover tools: `scripts/mcpcall.py --list`
6. Write `SKILL.md` with tool docs

## Step 1: Copy and Configure the Script

### No-auth variant

Edit `SERVER_URL`:

```python
SERVER_URL = "https://mcp.example.com/v1"
```

### Auth variant

Edit both constants:

```python
SERVER_URL = "https://mcp.example.com/v1"
ENV_VAR = "MY_API_KEY"
```

The script reads the API key from the environment variable at runtime — fully stateless.

## Step 2: Write SKILL.md

### Frontmatter

````yaml
---
name: my-mcp-skill
description: <what it does>. TRIGGER when <when to activate>.
allowed-tools:
  - Bash(*mcpcall.py*:*)
---
````

- `name` — kebab-case, matches directory name.
- `description` — concise capability + explicit TRIGGER clause.
- `allowed-tools` — glob pattern auto-approving mcpcall invocations.

### Body

````markdown
# My MCP Skill

<one-line description>. No API key required.

## Setup (auth variant only)

Requires `MY_API_KEY` environment variable:

```bash
export MY_API_KEY=<key>
```

## tool_name
<description>
- `param` (required): <what it is>

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/mcpcall.py tool_name param:"value"
```
````

### Argument Styles

**Key-value** — flat parameters (strings, numbers, booleans):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/mcpcall.py search query:"search terms" num:10 verbose:true
```

Type coercion: `true`/`false` → bool, integers → int, floats → float, else string.

**JSON** — arrays or objects:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/mcpcall.py classify --args '{"texts": ["a", "b"], "labels": ["x", "y"]}'
```

Both can be combined — kv_args as base, `--args` JSON merged on top.

## Skill Directory Layout

```
my-mcp-skill/
├── SKILL.md              # frontmatter + tool docs
└── scripts/
    └── mcpcall.py        # self-contained PEP 723 script (chmod +x)
```

## Live Examples

| Skill | Template | Server |
|---|---|---|
| `jina-ai` | auth | `https://mcp.jina.ai/v1` |
| `grep-app` | noauth | `https://mcp.grep.app` |
| `deepwiki` | noauth | `https://mcp.deepwiki.com/mcp` |
