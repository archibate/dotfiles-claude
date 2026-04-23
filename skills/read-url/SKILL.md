---
name: read-url
description: >
  Extract clean, complete text content (markdown) from any web page. Use this
  when reading articles, docs, GitHub READMEs, blog posts, social posts, or
  papers, or when the user says "read this page", "what does this link say",
  provides a URL to read, curl returns noisy HTML, or WebFetch returns
  truncated, summarized, or refused results.
allowed-tools:
  - Bash(npx defuddle*:*)
  - Bash(defuddle*:*)
  - WebFetch
---

# Read URL

Work down this fallback ladder in order. Each step is only tried when prior steps don't apply or fail.

## Fallback ladder

1. **Raw `.md` / `.txt` / plain-text URL** → `curl -sL <url>` (already clean, no HTML to strip)
2. **Known site** → use the dedicated CLI/API from the [routing table](#routing-table) below
3. **Generic site** (articles, docs, tech blogs, unknown) → `npx defuddle parse <url> --markdown` — see `references/defuddle.md`
4. **JS-rendered page** (defuddle returns empty / skeleton-only content) → `/agent-browser` skill
5. **Cloudflare / anti-bot protection** (Turnstile, blocked responses, 403/503) → `/scrapling` skill
6. **Still blocked and genuinely need this page** → ask the user to open it and paste the content, or offer the `/chrome-cdp` skill (requires explicit user approval first). Otherwise, give up and report the failure.

## Routing table

Step 2 — URLs matching a known domain:

| Domain / Pattern | Preferred path |
|---|---|
| `github.com` / `gist.github.com` | `gh api` / `gh repo view` / `gh gist view`; for a known file path: `curl -sL https://raw.githubusercontent.com/<owner>/<repo>/<ref>/<path>` |
| `x.com` / `twitter.com` / `t.co` | `curl -sL https://api.fxtwitter.com/<user>/status/<id> \| jq` |
| `bilibili.com` | `/bilibili-api` skill — fetches video title, description, comments |
| `youtube.com` / `youtu.be` | `yt-dlp --dump-json --skip-download` for title/description/metadata; `yt-dlp --write-auto-sub --sub-lang en --skip-download` for transcript |
| `arxiv.org` / `ssrn.com` | `/jina-ai` skill |
| `mp.weixin.qq.com` (微信公众号) | `/scrapling` skill — `scrapling extract get <url>` works without a browser |
| `instagram.com` | `instaloader` CLI |
| `reddit.com` | append `.json` to the URL, fetch with `curl` |

## vs. WebFetch

This skill returns full page text (markdown), parsed locally — no summarization, no information loss. WebFetch routes through a remote small model that may summarize, refuse, or truncate; reach for it only when you want an AI summary, not the content itself.

## When to bypass the ladder

- Need a **quick AI summary** → built-in WebFetch
- No specific URL yet, need to **search** → built-in WebSearch or `/jina-ai` skill
