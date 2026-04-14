# Stream JSON Protocol

The stream-json protocol is NDJSON (one JSON object per line) over stdin/stdout between your process and the `claude` subprocess.

## Stdout Events

### system — Session lifecycle

```json
{"type":"system","subtype":"init","session_id":"<uuid>"}
```

API retry (rate limit or server error):
```json
{"type":"system","subtype":"api_retry","attempt":1,"max_retries":3,"retry_delay_ms":1000,"error_status":429,"error":"rate_limit","session_id":"..."}
```

### assistant — Model output

Contains text and tool_use content blocks:
```json
{
  "type": "assistant",
  "message": {
    "id": "msg_01...",
    "content": [
      {"type": "text", "text": "Let me check that file."},
      {"type": "tool_use", "id": "toolu_01...", "name": "Read", "input": {"file_path": "/src/main.py"}}
    ],
    "usage": {"input_tokens": 150, "output_tokens": 45}
  }
}
```

### user — Tool results

Tool results fed back into the conversation:
```json
{
  "type": "user",
  "message": {
    "role": "user",
    "content": [{"tool_use_id": "toolu_01...", "type": "tool_result", "content": "file contents here"}]
  }
}
```

### result — Final output (always last)

```json
{
  "type": "result",
  "subtype": "success",
  "session_id": "...",
  "duration_ms": 4521,
  "duration_api_ms": 3100,
  "is_error": false,
  "num_turns": 3,
  "total_cost_usd": 0.0042,
  "result": "Done. File written.",
  "stop_reason": "end_turn",
  "structured_output": null,
  "usage": {"..."},
  "model_usage": {"claude-sonnet-4-6": {"inputTokens": 1200, "outputTokens": 80, "costUSD": 0.0042}}
}
```

### stream_event — Token-level streaming

Requires `--include-partial-messages`:
```json
{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"Hello"}},"session_id":"..."}
```

The `event` field contains raw Claude API streaming events: `message_start`, `content_block_start`, `content_block_delta` (with `text_delta` or `input_json_delta`), `content_block_stop`, `message_delta`, `message_stop`.

## Stdin Messages (Multi-Turn)

When using `--input-format stream-json`, send NDJSON user messages on stdin:

```json
{"type":"user","message":{"role":"user","content":"Your follow-up message"},"session_id":"default"}
```

Fields:
- `type`: `"user"` (only supported input type)
- `message.role`: `"user"`
- `message.content`: string or array of content blocks
- `session_id`: use `"default"` or the session UUID from the init event

**Note:** The stdin schema is not officially documented (GitHub #24594, closed "not planned"). Confirmed via SDK source and bug reports. Treat as stable but unofficial.

## Pipe-Chaining

Chain Claude instances via stream-json:
```bash
claude -p --output-format stream-json "Analyze auth.py" | \
  claude -p --input-format stream-json --output-format stream-json "Summarize security issues" | \
  claude -p --input-format stream-json "Generate fix tickets"
```

## Streaming Token Display

Extract streaming text with jq:
```bash
claude -p "Write a poem" \
  --output-format stream-json \
  --verbose \
  --include-partial-messages | \
  jq -rj 'select(.type == "stream_event" and .event.delta.type? == "text_delta") | .event.delta.text'
```

## Known Issues

- When using `--input-format stream-json` for multi-turn, session `.jsonl` files on disk accumulate duplicate entries (entire prior history re-appended each turn). Does not affect in-process functionality. Workaround: deduplicate by UUID when reading session files.
