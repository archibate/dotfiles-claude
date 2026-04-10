# Task Costs & I/O Dependencies

Measured resource costs and data dependencies for pipeline tasks. Referenced by `/preflight-check` skill.

## Cost Lookup Table

Measured costs for known tasks. **Costs are per-instance** — see batch rules below. Update this table when actual measurements differ from estimates.

| Task | Category | Runtime | Memory | Notes |
|---|---|---|---|---|
| _example task_ | Light | ~1 min | <1 GB | _description_ |

### Batch / Parallel Multiplier

The table above shows **per-instance** cost. When spawning N instances or batching many tasks, re-classify the **aggregate**:

```
Aggregate category = classify(per_instance_runtime × count / parallelism,
                              per_instance_memory × parallelism)
```

**Rule:** Any batch that results in aggregate runtime >1 hr or memory >10 GB is Heavy, regardless of per-instance category.

### Unknown Tasks

If a task is not in the table above, **treat as Heavy until measured**. After running with Step 1a (probe), record actual values here.

## I/O Dependency Table

| Task | Reads | Writes |
|---|---|---|
| _example task_ | _input files_ | _output files_ |

### Unknown Tasks

If a task is not in the table above, **assume it may conflict with anything** until verified:

1. Read the script source to identify file reads/writes
2. Check CLI `--help` for `--input`, `--output` flags
3. Add the task to this table after verification

### Critical Shared Files

List files that are written by one task and read by many others — these are the most common conflict sources.

- _example: `data/processed.parquet` — written by preprocessing, read by training and evaluation_
