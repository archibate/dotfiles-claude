---
name: jina-ai
description: >
  Region-aware web search, academic papers (arXiv/SSRN), PDF extraction, BibTeX, and image search via Jina AI.
  This skill should be used when the user says "search in Japanese", "搜中文内容", "find papers on arXiv",
  "search for images of", "get BibTeX", or when needing to search in specific languages/regions
  (gl/hl for local community content), find academic papers, extract figures from PDFs, or search for images.
allowed-tools:
  - Bash(*mcpcall.py*:*)
---

# Jina AI

Call Jina MCP tools via `scripts/mcpcall.py` for web content extraction, search, academic research, embeddings-based NLP, and visual capture.

## Setup

Requires `JINA_API_KEY` environment variable (get one at [jina.ai/api-key](https://jina.ai/api-key)):

```bash
export JINA_API_KEY=<key>
```

## Web Reading ⚠️ Unreliable — use defuddle or WebFetch instead

### read_url ❌
Extract web page content as clean markdown. Supports single URL or array of URLs.
- `url` (required): URL string or array of URLs
- `withAllLinks`: extract all hyperlinks as structured data
- `withAllImages`: extract all images as structured data

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/mcpcall.py read_url url:"https://example.com"
${CLAUDE_PLUGIN_ROOT}/scripts/mcpcall.py read_url url:"https://example.com" withAllLinks:true
```

### parallel_read_url ❌
Read up to 5 URLs in parallel for batch extraction.
- `urls` (required): array of `{url, withAllLinks?, withAllImages?}` objects
- `timeout`: milliseconds (default 30000)

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/mcpcall.py parallel_read_url --args '{"urls": [{"url": "https://a.com"}, {"url": "https://b.com"}]}'
```

## Web Search

### search_web
Search the web for current information. Supports single query or array of queries for parallel search.
- `query` (required): search terms (string or array)
- `num`: max results 1-100 (default 30)
- `tbs`: time filter — `qdr:h` (hour), `qdr:d` (day), `qdr:w` (week), `qdr:m` (month), `qdr:y` (year)
- `gl`: country code (e.g. `cn`)
- `hl`: language code (e.g. `zh-cn`)
- `location`: location string (e.g. `Shanghai`)

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/mcpcall.py search_web query:"search terms" num:10
${CLAUDE_PLUGIN_ROOT}/scripts/mcpcall.py search_web query:"关键词" gl:cn hl:zh-cn
${CLAUDE_PLUGIN_ROOT}/scripts/mcpcall.py search_web query:"recent news" tbs:qdr:w
```

### parallel_search_web
Run up to 5 web searches in parallel for broader coverage.
- `searches` (required): array of `{query, num?, tbs?, gl?, hl?, location?}`
- `timeout`: milliseconds (default 30000)

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/mcpcall.py parallel_search_web --args '{"searches": [{"query": "topic A"}, {"query": "topic B", "num": 5}]}'
```

### search_images
Search for images across the web (like Google Images). Returns base64 JPEG by default.
- `query` (required): image search terms
- `return_url`: set `true` to get URLs instead of base64
- `tbs`, `gl`, `hl`, `location`: same as `search_web`

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/mcpcall.py search_images query:"neural network diagram"
${CLAUDE_PLUGIN_ROOT}/scripts/mcpcall.py search_images query:"logo" return_url:true
```

## Academic Research

### search_arxiv
Search arXiv for academic papers in STEM fields.
- `query` (required): search terms, author names, or topics (string or array)
- `num`: max results 1-100 (default 30)
- `tbs`: time filter

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/mcpcall.py search_arxiv query:"transformer attention" num:10
${CLAUDE_PLUGIN_ROOT}/scripts/mcpcall.py search_arxiv query:"reinforcement learning" tbs:qdr:m
```

### parallel_search_arxiv
Run up to 5 arXiv searches in parallel for comprehensive coverage.
- `searches` (required): array of `{query, num?, tbs?}`
- `timeout`: milliseconds (default 30000)

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/mcpcall.py parallel_search_arxiv --args '{"searches": [{"query": "topic A"}, {"query": "topic B"}]}'
```

### search_ssrn
Search SSRN for social science, economics, law, finance papers.
- `query` (required): search terms (string or array)
- `num`: max results 1-100 (default 30)
- `tbs`: time filter

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/mcpcall.py search_ssrn query:"market microstructure" num:10
```

### parallel_search_ssrn
Run up to 5 SSRN searches in parallel.
- `searches` (required): array of `{query, num?, tbs?}`
- `timeout`: milliseconds (default 30000)

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/mcpcall.py parallel_search_ssrn --args '{"searches": [{"query": "topic A"}, {"query": "topic B"}]}'
```

### search_bibtex
Search DBLP + Semantic Scholar, return BibTeX citations.
- `query` (required): paper title, topic, or keywords
- `author`: filter by author name
- `year`: minimum publication year
- `num`: max results 1-50 (default 10)

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/mcpcall.py search_bibtex query:"attention is all you need"
${CLAUDE_PLUGIN_ROOT}/scripts/mcpcall.py search_bibtex query:"deep learning" author:Hinton year:2020 num:5
```

## PDF & Screenshots

### extract_pdf
Extract figures, tables, and equations from PDFs using layout detection.
- `id`: arXiv paper ID (e.g. `2301.12345`)
- `url`: direct PDF URL
- `type`: filter by `figure`, `table`, `equation` (comma-separated)
- `max_edge`: max image edge size in px (default 1024)

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/mcpcall.py extract_pdf id:2301.12345
${CLAUDE_PLUGIN_ROOT}/scripts/mcpcall.py extract_pdf url:"https://example.com/paper.pdf" type:figure
```

### capture_screenshot_url ❌ Use agent-browser instead
Capture web page screenshots as base64 JPEG.
- `url` (required): page URL
- `firstScreenOnly`: `true` for viewport only (faster), `false` for full page
- `return_url`: `true` to get URL instead of base64

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/mcpcall.py capture_screenshot_url url:"https://example.com"
${CLAUDE_PLUGIN_ROOT}/scripts/mcpcall.py capture_screenshot_url url:"https://example.com" firstScreenOnly:true
```

## NLP & Embeddings

### classify_text
Classify texts into user-defined labels using Jina embeddings.
- `texts` (required): array of strings to classify
- `labels` (required): array of label strings
- `model`: embedding model (default `jina-embeddings-v5-text-small`)

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/mcpcall.py classify_text --args '{"texts": ["great product", "terrible"], "labels": ["positive", "negative", "neutral"]}'
```

### sort_by_relevance
Rerank documents by relevance to a query using Jina Reranker.
- `query` (required): the query to rank against
- `documents` (required): array of document texts
- `top_n`: max results to return

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/mcpcall.py sort_by_relevance --args '{"query": "machine learning", "documents": ["doc1 text", "doc2 text"], "top_n": 5}'
```

### deduplicate_strings
Select top-k semantically unique strings from a list.
- `strings` (required): array of strings
- `k`: number to return (auto-optimized if omitted)

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/mcpcall.py deduplicate_strings --args '{"strings": ["hello world", "hi world", "goodbye"]}'
```

### deduplicate_images
Select top-k visually unique images using CLIP v2 embeddings.
- `images` (required): array of image URLs or base64 strings
- `k`: number to return (auto-optimized if omitted)

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/mcpcall.py deduplicate_images --args '{"images": ["https://a.com/1.jpg", "https://a.com/2.jpg"]}'
```

### expand_query
Rewrite a search query into multiple expanded variants for deeper research.
- `query` (required): the query to expand

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/mcpcall.py expand_query query:"machine learning optimization"
```

## Utility

### primer
Get current session context (time, location, network) for localized responses. No parameters.

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/mcpcall.py primer
```

### guess_datetime_url
Guess when a web page was last updated/published.
- `url` (required): page URL

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/mcpcall.py guess_datetime_url url:"https://example.com/article"
```

### search_jina_blog
Search Jina AI's official blog and news.
- `query` (required): search terms (string or array)
- `num`: max results 1-100 (default 30)
- `tbs`: time filter

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/mcpcall.py search_jina_blog query:"embeddings" num:10
```

### show_api_key
Show the current Jina API key for this session. No parameters.

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/mcpcall.py show_api_key
```

## Tool Selection Guide

| Scenario | Tool | Notes |
|---|---|---|
| Read a web page | **defuddle** or **WebFetch** | |
| General web search | **WebSearch** (built-in) | |
| Region/language-specific search | `search_web` with `gl`/`hl` | e.g. `gl:jp hl:ja` for Japanese results |
| Find STEM papers | `search_arxiv` | Jina's strength |
| Find social science / finance papers | `search_ssrn` | Jina's strength |
| Get BibTeX citations | `search_bibtex` | Jina's strength |
| Extract figures from a paper | `extract_pdf` | Jina's strength |
| Find images | `search_images` | |
| Categorize text into labels | `classify_text` | |
| Rank documents by relevance | `sort_by_relevance` | |
| Remove duplicate content | `deduplicate_strings` / `deduplicate_images` | |

## Tips

- Use `expand_query` before `parallel_search_web` or `parallel_search_arxiv` to generate diverse queries for thorough research.
- Parallel variants accept up to 5 items — use them for batch work.
- Set `tbs:qdr:w` to restrict results to the past week for time-sensitive queries.
- For Chinese-language results, set `gl:cn hl:zh-cn` on search tools.
- `${CLAUDE_PLUGIN_ROOT}/scripts/mcpcall.py --list jina` to see all available tools.
