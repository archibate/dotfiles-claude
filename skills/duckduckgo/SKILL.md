---
name: duckduckgo
description: Use this skill for web search and content scraping via DuckDuckGo.
---

# DuckDuckGo Search
Use DuckDuckGo MCP by executing shell commands.

## Web search
- `npx -y mcporter call --stdio 'uvx duckduckgo-mcp-server' search query="{keyword}" max_results=10`

## Web fetch
- `npx -y mcporter call --stdio 'uvx duckduckgo-mcp-server' fetch_content url="https://..."`
