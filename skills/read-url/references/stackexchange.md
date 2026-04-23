# Stack Exchange API

Stack Overflow / Stack Exchange pages put the question and answers in sibling DOM blocks, so defuddle returns only the question. Use the API instead.

## Site parameter

The `site=` query string uses short names, not full domains:

| Domain | `site=` |
|---|---|
| `stackoverflow.com` | `stackoverflow` |
| `superuser.com` | `superuser` |
| `serverfault.com` | `serverfault` |
| `askubuntu.com` | `askubuntu` |
| `unix.stackexchange.com` | `unix` |
| `math.stackexchange.com` | `math` |
| `mathoverflow.net` | `mathoverflow.net` |
| Other `*.stackexchange.com` | subdomain (e.g. `tex`, `stats`, `apple`) |

Full list: `curl -sL 'https://api.stackexchange.com/2.3/sites?pagesize=500' | jq -r '.items[] | "\(.api_site_parameter)\t\(.site_url)"'`.

## Question ID from URL

URLs look like `https://<site>/questions/<id>/<slug>` — strip everything except `<id>`.

## Fetch answers as markdown

Filter `!6WPIomnJRWnar` returns `body_markdown` instead of the default HTML `body`:

```bash
curl -sL "https://api.stackexchange.com/2.3/questions/<id>/answers?site=<site>&filter=!6WPIomnJRWnar&order=desc&sort=votes" \
  | jq -r '.items[] | "## Answer (score \(.score)\(if .is_accepted then ", accepted" else "" end))\n\n\(.body_markdown)\n"'
```

The markdown still contains HTML entities (`&quot;`, `&#39;`, `&amp;`). Unescape with the companion script:

```bash
... | ~/.claude/skills/read-url/scripts/html-unescape.py
```

## Fetch question body too

Same filter works on the question endpoint:

```bash
curl -sL "https://api.stackexchange.com/2.3/questions/<id>?site=<site>&filter=!6WPIomnJRWnar" \
  | jq -r '.items[0] | "# \(.title)\n\n\(.body_markdown)"'
```

## Rate limit

Anonymous requests are capped at 300/day per IP. Check `quota_remaining` in the response. Authenticated keys get 10k/day but aren't needed for casual reads.
