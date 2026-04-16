---
name: defuddle
description: >
  Extract clean, complete markdown from web pages using Defuddle CLI, removing navigation and ads.
  This skill should be used when reading articles, docs, GitHub READMEs, blog posts, or when
  the user says "read this page", "what does this link say", provides a URL to read, or when
  WebFetch returns truncated/summarized/refused results. Returns original content without summarization.
allowed-tools:
  - Bash(npx defuddle*:*)
---

# Defuddle

Extract clean readable content from web pages via `npx defuddle`. Removes navigation, ads, sidebars — returns only the main content as markdown. Saves tokens compared to WebFetch.

## Usage

Use `--markdown` for markdown output:

```bash
npx defuddle parse <url> --markdown
```

Save to file:

```bash
npx defuddle parse <url> --markdown --output content.md
```

Extract metadata only:

```bash
npx defuddle parse <url> --property title
npx defuddle parse <url> --property description
```

## Why defuddle over WebFetch

- defuddle returns the **complete original content** as markdown — no summarization, no information loss
- WebFetch uses a small model that may summarize, refuse, or misinterpret the content
- defuddle runs locally (no API), WebFetch goes through a remote model

## When to use

- Articles, blog posts, documentation pages → defuddle
- GitHub repo pages (get clean README) → defuddle
- Need complete, unmodified page content → defuddle
- Raw text / .md URLs → WebFetch (already clean, no HTML to strip)
- Need a quick AI-generated summary → WebFetch
- Search the web → WebSearch (built-in)

## Notes

- No API key needed, runs locally via npx
- First run downloads the package, subsequent runs use cache
