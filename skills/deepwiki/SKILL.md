---
name: deepwiki
description: >
  Query AI-generated overview of GitHub repositories via DeepWiki MCP. Use when
  needing a fast high-level understanding of a repository's architecture and
  design decisions without fetching full repository.
allowed-tools:
  - Bash(*mcpcall.py*:*)
---

# DeepWiki

AI-powered documentation for GitHub repositories. Browse auto-generated docs, explore topic structures, and ask questions about any public repo. Powered by [DeepWiki](https://deepwiki.com) MCP. No API key required.

## read_wiki_structure

Get a list of documentation topics for a repository. Use this first to discover what's documented.

- `repoName` (required): GitHub repo in `owner/repo` format

```bash
scripts/mcpcall.py read_wiki_structure repoName:"facebook/react"
scripts/mcpcall.py read_wiki_structure repoName:"anthropics/claude-code"
```

## read_wiki_contents

View full documentation about a repository.

- `repoName` (required): GitHub repo in `owner/repo` format

```bash
scripts/mcpcall.py read_wiki_contents repoName:"facebook/react"
scripts/mcpcall.py read_wiki_contents repoName:"pallets/flask"
```

## ask_question

Ask any question about a repository and get an AI-powered, context-grounded response.

- `repoName` (required): GitHub repo (`owner/repo` string) or array of up to 10 repos
- `question` (required): the question to ask

### Single repo

```bash
scripts/mcpcall.py ask_question repoName:"facebook/react" question:"How does the reconciliation algorithm work?"
scripts/mcpcall.py ask_question repoName:"pallets/flask" question:"How are blueprints registered?"
```

### Cross-repo comparison (up to 10 repos)

```bash
scripts/mcpcall.py ask_question --args '{"repoName": ["pallets/flask", "django/django"], "question": "How do these frameworks handle middleware?"}'
```

## Tool Selection Guide

| Scenario | Tool |
|---|---|
| Discover what topics are documented | `read_wiki_structure` |
| Read full repo documentation | `read_wiki_contents` |
| Ask a specific question about a repo | `ask_question` |
| Compare multiple repos | `ask_question` with array of repos |

## Tips

- Start with `read_wiki_structure` to see available topics before diving into full contents.
- `ask_question` supports up to 10 repos at once for cross-project comparisons.
- Use `ask_question` for targeted queries — it's faster than reading full wiki contents.
- Works with any public GitHub repository.
- Responses are AI-generated and can hallucinate, especially on small/obscure repos. Always verify key claims against actual source code (use `/repo-cache` to clone and read).
