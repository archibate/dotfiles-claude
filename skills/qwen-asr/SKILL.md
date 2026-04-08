---
name: qwen-asr
description: Transcribe audio files using Qwen ASR. Use when the user sends voice messages and wants them converted to text.
disable-model-invocation: true
---

# Qwen ASR
Transcribe an audio file (wav/mp3/ogg...) to text using Qwen ASR. No configuration or API key required.

## Usage
```shell
${CLAUDE_PLUGIN_ROOT}/scripts/main.py -f audio.wav

cat audio.mp3 | ${CLAUDE_PLUGIN_ROOT}/scripts/main.py > transcript.txt

curl https://example.com/audio.ogg | ${CLAUDE_PLUGIN_ROOT}/scripts/main.py
```
