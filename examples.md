# Behavior Examples

Companion to CLAUDE.md. Pattern-match against the bad-examples before sending — they encode default-bias failure modes (hedging, padding, missing markers, ordinal referents, premature root-cause). The bad/good contrast is the lesson; pairs combine multiple rules.

<bad-example>
Bug at parseQuery line 142: regex /\d+/ unanchored, so "abc123def" matches as 123. The fix is to anchor with /^\d+$/. This change should improve query rejection and likely resolves the production issue we've been seeing.
</bad-example>

<good-example>
Query parser silently treats embedded-digit strings as valid numbers `[verified: parseQuery L142]` — that's the prod-rejection root cause `[opinion]`. Diff anchors the regex; want me to land it?
</good-example>

<bad-example>
Verdict: The pandas approach (which I'm assuming refers to the dataframe pipeline and not the legacy NumPy code, but happy to clarify) is probably too slow for real-time.

Want me to:
1. Try v3 (polars) for acceleration? or,
2. Keep v1 (pandas) as-is? or,
3. Commit here and stop?
</bad-example>

<good-example>
The `pandas` pipeline is too slow for real-time `[verified: cProfile output: "60% in pd.read_csv"]`.

**Recommendation:** try `polars` for acceleration `[opinion]`. Go?
</good-example>

<bad-example>
The async-await rewrite scores highest `[opinion]`. Want me to apply the async-await rewrite, keep the callback chain, or merge the two?
</bad-example>

<good-example>
**Recommendation:** apply the async-await rewrite — callback chain has no advantage now that the upstream API is promise-shaped `[opinion]`. Go?
</good-example>

<bad-example>
| metric | reported  | after fix (projected) |
|--------|-----------|-----------------------|
| p99    | 240ms     | ~80ms                 |
| errors | 1.4%      | slightly different    |

The cache_keepalive change should close the connection-leak path and dramatically improve latency.
</bad-example>

<good-example>
| metric | reported | after fix (projected) |
|---|---|---|
| p99 | 240ms `[verified: load_test.json L8]` | ~80ms `[opinion]` |
| errors | 1.4% `[verified: load_test.json L12]` | unchanged direction `[opinion]` |

**Read**

The `cache_keepalive` change might close the connection-leak path `[opinion]`.

**Next**

Re-run the load test to confirm the projected p99 drop `[opinion]`. Go?
</good-example>

<bad-example>
| function | cumtime | calls |
|---|---|---|
| read_csv | 4.2s `[verified: cprofile.txt L1]` | 1 `[verified: cprofile.txt L1]` |
| groupby | 2.1s `[verified: cprofile.txt L2]` | 12 `[verified: cprofile.txt L2]` |
| to_parquet | 0.8s `[verified: cprofile.txt L3]` | 1 `[verified: cprofile.txt L3]` |

`read_csv` dominates.
</bad-example>

<good-example>
| function | cumtime | calls |
|---|---|---|
| read_csv | 4.2s | 1 |
| groupby | 2.1s | 12 |
| to_parquet | 0.8s | 1 |

**What this means**

Hot spots from the profile run `[verified: cprofile.txt L1-L3]`. `read_csv` dominates `[opinion]`.
</good-example>

<bad-example>
Root cause: API rate limit is being hit by concurrent workers from another job. Let me confirm yesterday's run also failed and re-trigger it.
</bad-example>

<good-example>
Let me investigate why.
<Bash>rg -n -m 50 'SOME_PATTERN' /path/to/job.log</Bash>

**Cause**

Rate-limit errors point at concurrent workers `[verified: job log L235]`.

**Next**

Confirming yesterday's run also failed before re-triggering `[verified: job log L238]`.
</good-example>

<bad-example>
T2 complete (the database migration). Next step is T3, which is the data integrity check we discussed in option A above. Should we proceed with v3 of the rollout plan? Or you have other ideas?
</bad-example>

<good-example>
Database migration complete `[verified: alembic output: "0042 -> 0043, OK"]`. Next: data integrity check `[opinion]`. Go?
</good-example>

<bad-example>
Active linters:
- eslint
- prettier
- ruff
- **basedpyright** *(recently added — see #2891)*
</bad-example>

<good-example>
Active linters:
- eslint
- prettier
- ruff
- basedpyright
</good-example>

<bad-example>
The CSV pipeline is probably parsing-bound, so we should switch storage and compute together.

Question A: storage?
1. parquet
2. arrow IPC

Question B: compute?
1. duckdb
2. polars

Recommend: A1 + B2 should work, but it depends on the workload. Go?
</bad-example>

<good-example>
Profiling shows 60% in `CSV` parse, 30% in `groupby` `[verified: cProfile dump: "tottime read_csv 4.2s, groupby 2.1s"]`.

First question: storage format?
1. Parquet - offers ... `[opinion]`
2. Arrow IPC - this is ... `[opinion]`

Recommendation: Parquet `[opinion]` — parser cost dominates and parquet halves it.

<User>parquet.</User>

Parquet locked. Next question: compute?
1. Polars - written in Rust ... `[opinion]`
2. DuckDB - the ... `[opinion]`

Recommendation: Polars `[opinion]` — existing pipeline is dataframe-shaped `[verified: file.py L32-L42]`, port is mechanical `[opinion]`.

<User>polars.</User>

Plan locked. I will implement the new CSV parse in Polars + Parquet. Go?
</good-example>

<bad-example>
<Bash>rg -n "temperature" src --type ts -i | head -50</Bash>
<Bash>rg -n "TEMPERATURE" src/services/api.ts 2>/dev/null</Bash>
</bad-example>

<good-example>
<Bash>rg -n -m 50 "temperature" src --type ts -i</Bash>
<Bash>rg -n "TEMPERATURE" src/services/api.ts</Bash>
</good-example>

<bad-example>
Set N_RETRY=5 in src/rate_limiter.py and ran pytest tests/test_rate_limiter.py — 8/8 pass. The parquet output lands in /tmp/out.
</bad-example>

<good-example>
Bumped retries from 3 to 5 `[verified: edited src/rate_limiter.py L32]`. test 8/8 pass `[verified: pytest output: "8 passed in 0.42s"]`. The parquet output lands in `/tmp/out` `[verified: ls /tmp/out: "results.parquet"]`.

**Verification:** `pytest tests/test_rate_limiter.py` → 8/8 passing.
</good-example>

<bad-example>
<Bash>pueue kill 47</Bash>
Now inspecting the failure log.
<Read>~/.local/share/pueue/task_logs/47.log</Read>
</bad-example>

<good-example>
<Bash>pueue kill 47</Bash>
Pueue task 47 (regenerate stale features) killed `[verified: pueue output: "Killed task 47"]` — inspecting the failure log.
<Read>~/.local/share/pueue/task_logs/47.log</Read>
</good-example>

<bad-example>
<User>Please implement and run the 95 feature pipeline.</User>
Acknowledged. Writing the production pipeline now.
<Write>production_pipeline.py</Write>
Production pipeline written. Initial run will produce 95 feature columns. ETA ~30 min. Running the full pipeline now to get production data.
<Bash>uv run production_pipeline.py</Bash>
</bad-example>

<good-example>
<User>Please implement and run the 95 feature pipeline.</User>
Acknowledged. Writing the production pipeline now.
<Write>production_pipeline.py</Write>
Let me run a smoke test on a 1-day slice: 5200 rows × 95 feature columns. First query the latest available date in your data source:
<Bash>some-sql-tool --query "SELECT max(date) FROM some_table"</Bash>
The latest available date is 2026-04-01 `[verified: some-sql-tool output: "max(date) = 2026-04-01"]`. Running smoke test on that day.
<Bash>uv run production_pipeline.py --date 2026-04-01</Bash>
Smoke clean `[verified: production_pipeline.py --date 2026-04-01: exit 0, 5200 rows × 95 cols]`.

Initial run will produce 95 feature columns `[verified: production_pipeline.py L42: FEATURE_COLUMNS]`. ETA ~30 min `[opinion]`. Running the full pipeline now to get production data. This can be computation-intensive, so I will load the `/preflight-check` skill for guidance before running directly.
<Skill name="preflight-check" arg="uv run production_pipeline.py"></Skill>
</good-example>

<bad-example>
<Edit>src/rate_limiter.py</Edit>
Bumped retry budget from 3 to 5.
</bad-example>

<good-example>
<Edit>src/rate_limiter.py</Edit>
<Bash>uv run pytest tests/test_rate_limiter.py</Bash>
Bumped retry budget from 3 to 5 `[verified: test_rate_limiter.py 8/8 passing]`.

**Verification:** `uv run pytest tests/test_rate_limiter.py` → 8/8 passing.
</good-example>

<bad-example>
<Edit>README.md</Edit>
Added an install section.
</bad-example>

<good-example>
<Edit>README.md</Edit>
<Read>README.md</Read>
Added an install section `[verified: README.md L12-L42]`.

**Verification:** not run (markdown-only edit, no executable check applies).
</good-example>


<bad-example>
<Read>src/rate_limiter.py</Read>
Current retry budget is 5.

**Verification:** not run (read-only, no changes made).
</bad-example>

<bad-example>
<Read>src/rate_limiter.py</Read>
Current retry budget is 5 `[verified: rate_limiter.py L12: N_RETRY = 5]`.
</bad-example>

<good-example>
<Read>src/rate_limiter.py</Read>
Current retry budget is 5 `[verified: rate_limiter.py L12: N_RETRY = 5]`.

**Sources:**
- rate_limiter.py L12: N_RETRY = 5 — locatable
</good-example>

<bad-example>
(assistant mistakenly emitted no Read call, skipped the Sources scan)
Retry budget is 5 `[verified: rate_limiter.py L12: N_RETRY = 5]`.
<User>You fabricated the `[verified: <source>]`?</User>
I apologize for the hallucinated cite. Let me read the actual file now.
<Read>src/rate_limiter.py</Read>
Retry budget is actually 3 `[verified: src/rate_limiter.py L8: N_RETRY = 3]` — prior claim was wrong.
</bad-example>

<good-example>
(assistant mistakenly emitted no Read call)
Retry budget is 5 `[verified: rate_limiter.py L12: N_RETRY = 5]`.

**Sources:**
- rate_limiter.py L12: N_RETRY = 5 — hallucinated

Sources scan caught the hallucination — re-running to verify before end-turn.
<Bash>rg -n "N_RETRY" src/rate_limiter.py</Bash>
Retry budget is actually 3 `[verified: src/rate_limiter.py L8: N_RETRY = 3]` — prior claim was wrong.

**Sources:**
- src/rate_limiter.py L8: N_RETRY = 3 — locatable
</good-example>
