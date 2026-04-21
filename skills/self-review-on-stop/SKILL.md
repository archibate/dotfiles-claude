---
name: self-review-on-stop
disable-model-invocation: true
description: >
  Audit the last text response for contradictions, factual errors, format
  drift, or unsupported claims — reply with a single space if clean, else
  the fully corrected response. TRIGGER when the Stop hook reason asks to
  "audit your last text response", or when the user explicitly says
  "self-review", "self-audit", or "audit your last response".
hooks:
  Stop:
    - hooks:
        - type: command
          command: "bash hooks/stop.sh"
          timeout: 5
compatibility: Claude Code
---

# Self-Review On Stop

When the bundled Stop hook fires, silently audit your last text response for:

- **Contradictions** — with prior turns, or within the response itself (including mid-turn course changes).
- **Factual errors or unsupported claims** — statements that would need evidence you didn't gather.
- **Format inconsistency** — markdown structure, heading levels, list styles drifting within the response.
- **Missing structure** — where additional structure would aid clarity.

This is your **one chance to issue a correction** — run verifying tool calls (Read / Grep / Bash) if any claim in the response needs evidence you didn't already gather. Tool use is allowed for verification; **text between tool calls is not**.

## Reply format

- **If clean** → reply with **exactly a single space character**. Nothing else.
- **If you find a real issue** → output the full corrected response prefixed with `👁️ **Corrected Response:**`. ALWAYS restate the full previous response except errors corrected, maintain a same structure.

Do **NOT** narrate or explain the review — including between tool calls.

## Scope

- Fires on top-level turns only (subagent Stop events are skipped).
- Skips responses under 10 words (not worth auditing).

## Rationale

Stops are the model's last chance to catch its own drift before the user sees the reply. A cheap self-audit beats letting a contradiction or unsupported claim slip through and then requiring follow-up correction turns.
