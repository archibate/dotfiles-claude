# Defuddle

Extract clean readable content from generic web pages via `npx defuddle`. Removes navigation, ads, sidebars — returns only the main content as markdown.

## Usage

Markdown output:

```bash
npx defuddle parse <url> --markdown
```

Extract metadata only:

```bash
npx defuddle parse <url> --property title
npx defuddle parse <url> --property description
```

## Fallback when output is partial or wrong

Defuddle picks one primary content block, which fails on Q&A / multi-post / complex-layout pages where the wanted content lives in sibling DOM blocks. If the raw `curl -sL <url>` returns full HTML but defuddle's output drops sections, slice by CSS selector — see `html-selector.md`.
