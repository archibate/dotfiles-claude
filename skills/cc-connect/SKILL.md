---
name: cc-connect
description: >
  Send images, files, and notifications to the user via Discord, Feishu, or Telegram.
  TRIGGER when agent generates a plot/chart/screenshot and wants to deliver it; agent creates
  a report/PDF the user should receive; agent needs to notify the user (task completed, alert,
  reminder); user asks to "send image", "show me the chart", "notify me", "send to Telegram",
  "发到飞书"; user says "monitor tasks", "set up monitoring cron", "watch progress",
  "notify me of progress"; or when starting a multi-step pipeline that runs >30 min.
  Do NOT TRIGGER when not inside a cc-connect session (`CC_PROJECT` set)
version: 0.1.0
compabibility: cc-connect
---

# cc-connect: Send Images, Files, and Notifications

Claude Code cannot send images or files back to users through the terminal.
cc-connect bridges this gap via messaging platforms (Discord, Feishu, Telegram).

## Quick Reference

| I want to... | Reference |
|---|---|
| Send an image, file, or notification | `references/send-artifacts.md` |
| Set up periodic task monitoring with cron | `references/task-monitoring.md` |

## Requirements

- cc-connect daemon must be running: `cc-connect daemon status`
- `attachment_send = "on"` in `~/.cc-connect/config.toml` (for image/file sending)
- For image/file sending: cc-connect >= v1.2.2-beta (`cc-connect --version`)
- For task monitoring cron: must be inside a cc-connect session (`CC_PROJECT` set)
