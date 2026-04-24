---
name: joke
description: Fetch a random joke from jokeapi.dev. Use whenever the user asks for a joke, wants to be cheered up, asks to hear something funny, or requests a category-specific joke like "tell me a programming joke" or "give me a pun". Not for writing original jokes from scratch — this pulls from the public joke corpus.
disable-model-invocation: true
---

# Joke

Pulls a single random joke from `v2.jokeapi.dev` via the bundled script. Safe-mode is on by default so the returned joke won't contain NSFW, racist, sexist, political, religious, or explicit content.

## When to use

Trigger on any request to *hear* a joke — "tell me a joke", "make me laugh", "cheer me up", "got any good ones?", or category-flavored variants like "tell me a programming joke", "hit me with a pun", "a dark one". The intent is a ready-made joke, not original comedy.

Skip when the user wants you to *write* a joke, analyze one, or riff on a topic they've given you — none of that benefits from pulling a random joke off an API.

## The script

```
scripts/fetch_joke.py [options]
```

| Flag | Meaning |
|---|---|
| `-c, --category` | One of `Any` (default), `Programming`, `Misc`, `Pun`, `Spooky`, `Christmas`, `Dark` |
| `--unsafe` | Allow flagged content (NSFW / racist / sexist / religious / political / explicit). Off by default — only pass if the user explicitly asks for an unfiltered joke |
| `--json` | Print the full API response instead of the rendered joke. Useful if you want the category / flags for follow-up |

The script prints the joke to stdout (two lines for setup+delivery, one line for single-liners) and exits 0. On API error it writes to stderr and exits 1.

## Common invocations

**Random joke**
```bash
uv run scripts/fetch_joke.py
```

**Programming joke**
```bash
uv run scripts/fetch_joke.py -c Programming
```

**Dark humor (user asked for it)**
```bash
uv run scripts/fetch_joke.py -c Dark --unsafe
```

## Reporting back

Just show the joke. No preamble like "Here's a joke for you:" — the user asked, the joke answers. If the user asks why a joke is funny, explain the wordplay; otherwise let the joke speak.
