# GitHub

## Known file path (preferred)

Pure read, no auth, no rate-limit hit:

```bash
curl -sL https://raw.githubusercontent.com/<owner>/<repo>/<ref>/<path>
```

Use this whenever you have an explicit file path. For wiki pages: `https://raw.githubusercontent.com/wiki/<owner>/<repo>/<page>.md`.

## Issue or PR body + comments

```bash
gh issue view <n> -R <owner>/<repo> --json title,body,state,author,comments,labels
gh pr   view <n> -R <owner>/<repo> --json title,body,state,author,comments,files,reviews
```

Alternatively, pass a URL instead of `<n> -R ...`:

```bash
gh issue view https://github.com/<owner>/<repo>/issues/<n> --json ...
```

The `comments` field returns an array of `{author, body, createdAt}` — no need for a separate call.

## Search issues / PRs

Anonymous, no `gh api` needed (60 req/hr limit):

```bash
curl -sL 'https://api.github.com/search/issues?q=is:issue+<query>&per_page=10' | jq
```

The GitHub search API requires `is:issue` or `is:pull-request` in the query — a bare keyword search will return HTTP 422. Other useful qualifiers: `repo:<owner>/<repo>`, `author:<user>`, `label:<label>`, `state:open`, `in:title`.

Modern gh (≥2.6) also has `gh search issues <query>` / `gh search prs <query>` — same underlying API, cleaner output.

## Repo / gist metadata

```bash
gh repo view <owner>/<repo> --json name,description,defaultBranchRef,stargazerCount,languages,readme
gh gist view <id>
```

## Avoid `gh api`

`gh api` is NOT in `allowed-tools` and shouldn't be reached for casually. It's broad (can write via `-X POST/PATCH/DELETE`), counts against your token's rate limit, and the paths covered above handle 95% of read cases. If you genuinely need a REST endpoint not accessible via `gh repo/issue/pr/gist view`, prefer anonymous `curl https://api.github.com/...` first.
