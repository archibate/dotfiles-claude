---
name: tldr
description: Append a one-line summary to a long prior response so the user can fast-read the verdict. Use after outputing a final text response >=10 lines.
---

After a final text response >=10 lines, append exactly one line as a TLDR summary for the user to fast-read the verdict.

Format strictly:
  📌 <verdict in under 20 words>

Rules:
  - Write the verdict in the same language as your previous response.
  - Lead with the key verdict / answer / decision — not a recap of topics.
  - One sentence, hard cap 20 words.
  - No new information, no caveats, no bullet list.
  - Output ONLY that single summary line. Nothing else.
