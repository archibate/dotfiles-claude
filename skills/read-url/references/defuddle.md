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
