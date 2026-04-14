---
name: zhihu-post
description: >
  Write, refine, and validate a Chinese technical blog post for Zhihu (知乎). This skill
  should be used before drafting a long-form Chinese technical article — or when the user
  says "写博客", "知乎文章", "zhihu post", "write for zhihu".
---

# Zhihu Technical Blog Post

Write, iteratively refine, and validate a Chinese technical blog post formatted for Zhihu (知乎), which supports standard Markdown with LaTeX math blocks.

## When to Use

- Writing a technical blog post in Chinese based on research, exploration, or project work
- Converting a conversation or exploration session into a publishable article
- Refining an existing Chinese blog draft for publication

## When NOT to Use

- Short Q&A or informal notes (overkill)
- English-only publications
- Non-technical creative writing

## Workflow

### Phase 1: Draft

1. **Outline first.** Identify the narrative arc: problem, exploration, findings, solution, takeaways. Use numbered top-level sections (`## 一、`, `## 二、`, ...) for Chinese convention.
2. **Write in natural Chinese.** Not translated English. Avoid translationese (翻译腔). Technical terms can stay in English where that's the norm (e.g., "prompt caching", "TTL", "GrowthBook").
3. **Show the thought process.** Technical blog readers value the exploration journey — dead ends, surprising discoveries, pivots. Don't just present conclusions.
4. **Include quantitative evidence.** Tables, cost models, formulas. Use `$$...$$` for LaTeX math blocks (Zhihu renders these natively).
5. **Code snippets should be real.** Include file paths and line numbers when referencing source code. Readers should be able to verify.

### Phase 2: Attribution & Disclosure

6. **AI authorship disclosure.** If the article was written by or with Claude Code, state this clearly near the top (e.g., in a blockquote under the title). Describe the division of labor: who posed the questions, who did the research, who wrote the prose, who reviewed.
7. **Project references.** If there's a related open-source repo, config, or tool, add a dedicated section near the end. Be specific about what the repo contains — don't just drop a link. List the key files/directories and what each provides.

### Phase 3: Clear-Eye Review

Read the full article as if you're a stranger seeing it for the first time. Check for:

8. **Factual consistency.** Do numbers match across sections? If section 3 derives K < 11.5 and section 5 says "10 iterations", is the connection explained? Every concrete number should trace back to its derivation.
9. **Terminology precision.** Did you say "won't trigger tool calls" when you mean "won't trigger long-running tool calls"? Check every absolute claim.
10. **Cross-section coherence.** Do later sections contradict or subtly conflict with earlier ones? Check that rounding (e.g., "~57 min" vs "~58 min") is consistent.
11. **Domain leakage.** If the article is meant to be generic, check that domain-specific jargon (e.g., "train-test mismatch", "回测") hasn't leaked in. If domain-specific, ensure it's consistent throughout.
12. **Heading accuracy.** Does each section heading accurately describe the content? A section titled "which operations block X" shouldn't contain material about behavioral risks that aren't blocking.

### Phase 4: Iterate

13. **Fix each issue found in Phase 3.** One edit per issue, don't batch.
14. **Re-read after every batch of fixes.** Edits can introduce new inconsistencies. At least one full re-read after all fixes are applied.

### Phase 5: Validate Markdown

15. **Syntax check.** Run through `markdown-it` (with table extension) and verify no parse errors:

```bash
uv run --with markdown-it-py python -c "
import markdown_it, re
md = markdown_it.MarkdownIt('commonmark', {'html': True}).enable('table')
with open('FILEPATH') as f:
    text = f.read()
html = md.render(text)
tables = len(re.findall(r'<table>', html))
headings = len(re.findall(r'<h[1-6]>', html))
code_blocks = len(re.findall(r'<pre>', html))
latex_pairs = len(re.findall(r'\\\$\\\$', text)) // 2
print(f'Tables: {tables}, Headings: {headings}, Code blocks: {code_blocks}, LaTeX blocks: {latex_pairs}')
print('OK' if tables >= 0 and headings > 0 else 'WARNING: check output')
"
```

16. **Element count sanity.** Compare rendered element counts against what you expect. 0 tables when the source has pipe lines = rendering failure.
17. **Zhihu-specific checks:**
    - `$$...$$` LaTeX blocks render on Zhihu (standard)
    - Inline `$...$` also works on Zhihu
    - Tables must have header + separator row (`|---|---|`)
    - Zhihu strips raw HTML tags — don't rely on `<details>`, `<summary>`, etc.
    - Image links must be absolute URLs (Zhihu re-hosts images on upload)

### Phase 6: Final Output

18. **Report to user:** file path, word count, section count, and any remaining caveats (e.g., "LaTeX requires Zhihu's math mode to be enabled").
