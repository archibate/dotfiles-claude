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
  - Bash(curl:*)
  - Bash(jq:*)
  - Bash(rg:*)
  - Bash(npm view:*)
  - Bash(gh repo view:*)
  - Bash(gh gist view:*)
  - Bash(gh issue view:*)
  - Bash(gh pr view:*)
  - Bash(yt-dlp:*)
  - Bash(instaloader:*)
  - Bash(*html-select*:*)
  - Bash(*html-unescape*:*)
  - WebFetch
---

# Read URL

Work down this fallback ladder in order. Each step is only tried when prior steps don't apply or fail.

## Fallback ladder

1. **Raw `.md` / `.txt` / plain-text URL** → `curl -sL <url>` (already clean, no HTML to strip)
2. **Known site** → use the dedicated CLI/API from the [routing table](#routing-table) below
3. **Blog / newsletter / multi-post index** → try RSS first: `curl -sL <url>/feed` (also `/rss`, `/feed.xml`, `/atom.xml`, `/index.xml`). Most static-site generators and CMS platforms expose one; RSS gives you clean `<content:encoded>` or `<summary>` bodies without chrome
4. **Generic site** (articles, docs, tech blogs, unknown) → `npx defuddle parse <url> --markdown` — see `references/defuddle.md`
5. **JS-rendered page** (defuddle returns empty / skeleton-only content) → `/agent-browser` skill
6. **Cloudflare / anti-bot protection** (Turnstile, blocked responses, 403/503) → `/scrapling` skill
7. **Still blocked and genuinely need this page** → ask the user to open it and paste the content, or offer the `/chrome-cdp` skill (requires explicit user approval first). Otherwise, give up and report the failure.

## Routing table

Step 2 — URLs matching a known domain:

| Domain / Pattern | Preferred path |
|---|---|
| `github.com` / `gist.github.com` | File via `raw.githubusercontent.com`; issue/PR via `gh issue view` / `gh pr view`; search via anonymous `api.github.com/search/issues` — see `references/github.md` |
| `x.com` / `twitter.com` / `t.co` | `curl -sL https://api.fxtwitter.com/<user>/status/<id> \| jq` |
| `bilibili.com` | `/bilibili-api` skill — fetches video title, description, comments |
| `youtube.com` / `youtu.be` | `yt-dlp --dump-json --skip-download` for title/description/metadata; `yt-dlp --write-auto-sub --sub-lang en --skip-download` for transcript |
| `arxiv.org` / `ssrn.com` | `/jina-ai` skill |
| `mp.weixin.qq.com` (微信公众号) | `/scrapling` skill — `scrapling extract get <url>` works without a browser |
| `www.cnblogs.com` (博客园) | Plain defuddle works — server-rendered HTML with the article body inline. For a user's post index: `curl -sL 'https://www.cnblogs.com/<user>/rss'` (Atom feed) |
| `blog.csdn.net` (CSDN) | `/scrapling` skill — plain `curl` returns a JS-skeleton (content is JS-loaded) and defuddle hits 404 anti-bot. For a summary-only index: `curl -sL 'https://blog.csdn.net/<user>/rss/list'` returns RSS with 摘要 (not full bodies) |
| `zhihu.com` / `zhuanlan.zhihu.com` (知乎) | Hard — plain `curl` returns a bot-challenge page and even scrapling's `stealthy-fetch` gets 403 with empty content. Try `/chrome-cdp` with the user's logged-in session, or ask them to paste the content |
| `juejin.cn` (掘金) | `/scrapling` skill — Nuxt SPA; escalate to `/chrome-cdp` if stealthy-fetch returns only shell |
| `segmentfault.com` (思否) | `/scrapling` skill — custom HTTP 468 anti-bot; escalate to `/chrome-cdp` if stealthy-fetch fails |
| `weibo.com` (微博) | `/scrapling` skill — JS-rendered status pages; escalate to `/chrome-cdp` if stealthy-fetch returns only chrome |
| `xiaohongshu.com` (小红书) | `/scrapling` skill — aggressive anti-bot; escalate to `/chrome-cdp` if stealthy-fetch fails |
| `y.qq.com` (QQ 音乐) | Hard — `stealthy-fetch` returns the homepage shell instead of song data. Use `/chrome-cdp` with the user's logged-in session, or ask them to paste |
| `music.163.com` (网易云音乐) | Plain defuddle for basic info — `<title>` has song + artist. For lyrics / comments / playlists use the community-maintained `NeteaseCloudMusicApi` (self-hosted Node proxy over the internal API) |
| `wallstreetcn.com` (华尔街见闻) | Plain defuddle works — server-rendered with `_articleBody_…` class; no auth needed for public articles |
| `www.v2ex.com` (V2EX) | `curl -sL 'https://www.v2ex.com/api/topics/show.json?id=<id>' \| jq` — returns topic + full content; `api/replies/show.json?topic_id=<id>` for replies |
| `gitee.com` | **Known file path**: `curl -sL 'https://gitee.com/<owner>/<repo>/raw/<ref>/<path>'`. **Repo metadata**: `curl -sL 'https://gitee.com/api/v5/repos/<owner>/<repo>' \| jq`. Shape mirrors GitHub |
| `instagram.com` | `instaloader` CLI |
| `reddit.com` | Hard — `.json` endpoints are blocked since the 2023 API changes, and scrapling's `stealthy-fetch` gets a captcha page. Use the official OAuth API (PRAW / snoowrap) with credentials, or `/chrome-cdp` with the user's logged-in session |
| `stackoverflow.com` / `*.stackexchange.com` / `superuser.com` / `serverfault.com` / `askubuntu.com` | Stack Exchange API — see `references/stackexchange.md` |
| `*.fandom.com` | `/scrapling` skill — Fandom sits behind Cloudflare, plain `curl` returns the "Just a moment..." challenge regardless of path or User-Agent |
| Any other MediaWiki site — Wikipedia, Arch Wiki, cppreference, `*.wiki.gg`, etc. | Wikimedia-run wikis use the REST API + `prop=extracts`; third-party wikis use `?action=raw` or `api.php?action=parse` (some need defuddle due to heavy templates) — see `references/mediawiki.md` |
| `www.rfc-editor.org` / any RFC | `curl -sL 'https://www.rfc-editor.org/rfc/rfc<N>.txt'` — canonical plaintext, no chrome. `.html` and `.json` also available (the JSON has metadata like obsoleted-by, authors, status) |
| `peps.python.org` | Individual PEP: `curl -sL 'https://peps.python.org/pep-<N>/'` (clean HTML). All PEPs indexed: `curl -sL 'https://peps.python.org/api/peps.json' \| jq` — number, title, status, authors, created date |
| `news.ycombinator.com` | `curl -sL 'https://hn.algolia.com/api/v1/items/<id>' \| jq` — returns story + full comment tree as nested JSON |
| `pypi.org` | `curl -sL 'https://pypi.org/pypi/<package>/json' \| jq -r '.info.description'` for README; `.info.summary` / `.info.version` for metadata |
| `npmjs.com` / `registry.npmjs.org` | `npm view <package> readme` for README; `curl -sL 'https://registry.npmjs.org/<package>' \| jq` for full metadata |
| `lobste.rs` | append `.json` to the story URL (e.g. `lobste.rs/s/<id>.json`), fetch with `curl` |
| `dev.to` | `curl -sL 'https://dev.to/api/articles/<id>' \| jq -r '.title, .body_markdown'` — `<id>` is the numeric article ID |
| `*.substack.com` | `<subdomain>.substack.com/feed` — RSS with full post HTML in `<content:encoded>` |
| `medium.com` / `*.medium.com` | `curl -sL 'https://medium.com/feed/@<user>'` — RSS returns the last ~10 posts with full `content:encoded` HTML. Direct article URLs return a ~4KB paywall shell and need `/scrapling` if the piece isn't in the user's recent feed |
| `bsky.app` | `curl -sL 'https://public.api.bsky.app/xrpc/app.bsky.feed.getPostThread?uri=<at-uri>' \| jq` — no auth needed for public posts; convert `bsky.app/profile/<handle>/post/<rkey>` to `at://<handle>/app.bsky.feed.post/<rkey>` |
| `gitlab.com` | **Known file path** (preferred): `curl -sL https://gitlab.com/<owner>/<repo>/-/raw/<ref>/<path>`. **Repo metadata / MR / issue bodies**: `curl -sL 'https://gitlab.com/api/v4/projects/<owner>%2F<repo>' \| jq` (URL-encode the slash in the project path) |
| `codeberg.org` / any Gitea or Forgejo instance | **Known file path**: `curl -sL https://codeberg.org/<owner>/<repo>/raw/branch/<ref>/<path>`. **Metadata**: `curl -sL 'https://codeberg.org/api/v1/repos/<owner>/<repo>' \| jq` |
| `crates.io` | `curl -sL 'https://crates.io/api/v1/crates/<crate>' \| jq` for metadata; `.../<version>/readme` for README |
| `formulae.brew.sh` / any `brew` formula | `curl -sL 'https://formulae.brew.sh/api/formula/<name>.json' \| jq` — name, desc, versions, deps, caveats |
| `aur.archlinux.org` | `curl -sL 'https://aur.archlinux.org/rpc/v5/info/<pkg>' \| jq -r '.results[0]'` — Name, Version, Description, Maintainer, Depends, URL |
| `doi.org` / any bare DOI | `curl -sL 'https://api.crossref.org/works/<doi>' \| jq -r '.message \| .title[0], (.author[].family \| tostring)'` — reliable for title + authors + citation metadata (abstract hit-or-miss). Prefer `/jina-ai` or the publisher page for full text |
| Any Discourse forum (`discuss.python.org`, `meta.discourse.org`, `forum.rust-lang.org`, `discuss.pytorch.org`, etc.) | Append `.json` to the topic URL: `curl -sL '<forum>/t/<slug>/<id>.json' \| jq` — returns topic + all posts in `post_stream.posts` |
| `huggingface.co` | README via `<repo>/raw/main/README.md`; metadata via `/api/models`, `/api/datasets`, `/api/papers` — see `references/huggingface.md` |
| `web.archive.org` / any Wayback lookup | **Find closest snapshot**: `curl -sL 'https://archive.org/wayback/available?url=<url>&timestamp=<YYYYMMDD>' \| jq`. **Fetch raw archived response**: `curl -sL 'https://web.archive.org/web/<timestamp>id_/<url>'` — the `id_` suffix strips Wayback's toolbar injection and returns the original response body |
| `store.steampowered.com` | `curl -sL 'https://store.steampowered.com/api/appdetails?appids=<appid>&cc=us&l=en' \| jq -r '.["<appid>"].data'` — name, short_description, release_date, developers, categories, price |
| `speedrun.com` | `curl -sL 'https://www.speedrun.com/api/v1/games/<slug>' \| jq` — game metadata; further endpoints at `/games/<id>/categories`, `/runs?game=<id>` for leaderboards |
| Any WordPress site (self-hosted or `*.wordpress.com`) | `curl -sL '<site>/wp-json/wp/v2/posts?per_page=10' \| jq` for recent posts; `/wp-json/wp/v2/posts/<id>` for a single post (`.content.rendered` has the HTML body). Works on any WP install with the REST API enabled — still the default |
| `openlibrary.org` | `curl -sL 'https://openlibrary.org/works/OL<id>W.json' \| jq` for works; `/isbn/<isbn>.json` for ISBN lookup; `/authors/OL<id>A.json` for authors. Note: `.description` is sometimes a string, sometimes `{type, value}` — handle both |
| `gutenberg.org` (Project Gutenberg) | `curl -sL 'https://www.gutenberg.org/cache/epub/<id>/pg<id>.txt'` — full plaintext of out-of-copyright books |

## vs. WebFetch

This skill returns full page text (markdown), parsed locally — no summarization, no information loss. WebFetch routes through a remote small model that may summarize, refuse, or truncate; reach for it only when you want an AI summary, not the content itself.

## When to bypass the ladder

- Need a **quick AI summary** → built-in WebFetch
- No specific URL yet, need to **search** → built-in WebSearch or `/jina-ai` skill
