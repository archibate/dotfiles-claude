---
name: side-topic
description: >
  Preserve context when switching between main task and unrelated interruptions, then
  resume seamlessly. This skill should be used PROACTIVELY whenever the user introduces
  an unrelated topic mid-task — e.g. asks an ad-hoc question, requests a quick fix on a
  different file, or starts debugging a side issue while a multi-step plan is in progress —
  or when the user explicitly says "side topic", "quick question", "unrelated but",
  "before I forget", "btw", "oh also", or "back to what we were doing".
allowed-tools:
  - TaskCreate
  - TaskUpdate
  - TaskGet
  - TaskList
---

# Side Topic — Context Switch Protocol

Preserve progress on a main task when the user interrupts with an unrelated topic, then
resume cleanly afterward.

## When This Applies

- You are mid-way through a multi-step task (implementation, refactor, review, etc.)
- The user sends a message that is clearly unrelated to the current task
- Examples: "btw, can you check why tests fail?", "unrelated — what does X do?",
  "quick question about Y", or simply a new topic with no transition

## Before Switching Away

1. **Snapshot progress** — Update the task list to reflect exactly where you are:
   - Mark completed steps as done
   - Note the current in-progress step and any partial state (e.g. "edited file A, still
     need to update file B")
   - List remaining steps so nothing is lost
2. **Acknowledge the switch** — Tell the user briefly:
   > Pausing the main task (step N of M). Switching to your question.

## Handle the Interruption

- Address the side topic fully — don't rush or half-answer just to get back
- If the side topic itself is multi-step, track it with its own tasks

## After Resolving the Side Topic

1. **Check the task list** — Read back the saved state
2. **Summarize for the user** — Print a brief "back to main topic" recap:
   > Back to [task name]. Completed steps 1–3. Next up: step 4 — [description].
3. **Continue from exactly where you left off** — don't re-do completed work

## Nested Interruptions

If a second interruption arrives while handling the first side topic, apply the same
protocol recursively: snapshot the side topic's state before switching, and unwind in
order (most recent first) when returning.

## Edge Cases

- **Trivial question** (single-sentence answer, no context switch needed): Just answer
  inline and continue — no need for the full protocol.
- **User says "back to..."**: Treat as a signal to resume. Check the task list and print
  the recap even if the user didn't explicitly ask for one.
- **Ambiguous relevance**: If unsure whether the new topic is related to the current task,
  ask briefly: "Is this related to what we're working on, or a separate topic?"
