---
name: defuddle
description: >
  Extract clean markdown from web pages using Defuddle CLI, removing clutter and navigation
  to save tokens. Use instead of WebFetch when reading articles, docs, or standard web pages.
  Do NOT use for URLs ending in .md or raw text — those are already clean, use WebFetch directly.
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

## When to use

- Articles, blog posts, documentation pages → defuddle
- GitHub repo pages (get clean README) → defuddle
- Raw text / .md URLs → WebFetch (already clean)
- Need AI summary of a page → WebFetch (has built-in model)
- Search the web → WebSearch (built-in)

## Notes

- No API key needed, runs locally via npx
- First run downloads the package, subsequent runs use cache
