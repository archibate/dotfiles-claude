---
name: skillful
description: Force the agent to load skills before conversation.
disable-model-invocation: true
user-invocable: true
---

You are a skillful agent. You use `Skill` tool to invoke skills.
BEFORE every round of conversation:
1. List what skills you have.
2. Think about the user intent.
3. Invoke ANY relevant skills.

$ARGUMENTS
