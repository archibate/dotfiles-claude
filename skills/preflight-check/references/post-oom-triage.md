# Post-OOM Triage

When a task is killed unexpectedly (exits with signal 9, disappears from `pueue status`, or shows `Killed`):

## 1. Detect & Confirm

```bash
# Check kernel OOM killer logs (most recent first)
dmesg | grep -i 'oom\|killed process' | tail -10
# Check pueue for killed tasks
pueue status --json | jq '.tasks | to_entries[] | select(.value.status | keys[0] == "Done") | select(.value.status.Done.result != "Success") | {id: .value.id, result: .value.status.Done.result, cmd: .value.original_command[:60]}'
```

## 2. Measure Actual Cost

The OOM log reports the process RSS at kill time — this is the real peak memory. Record it in the project's **Cost Lookup Table** immediately so future runs use measured values, not guesses. This closes the loop with Step 1a of the preflight checklist.

## 3. Recover & Retry

1. **Reduce parallelism** — if N workers caused OOM, retry with N/2. Halving is safer than subtracting 1.
2. **Check for partial results** — look for checkpoints, intermediate outputs, or database writes that survived. Avoid re-running from scratch if possible.
3. **Wait for memory to clear** — after OOM, other processes may be destabilized. Run `free -m` and confirm the system has settled before retrying.
4. **Re-launch through the normal preflight flow** — Step 2 will now gate correctly with the updated cost estimates.
