**Tool calls** (assistant payload):

| Tool           | Tokens     | Share     | Cost     |
| -------------- | ---------: | --------: | -------: |
| Bash           | 889M       | 6.1%      | $267     |
| Write          | 772M       | 5.3%      | $232     |
| Edit           | 761M       | 5.2%      | $228     |
| Read           | 73M        | 0.5%      | $22      |
| Agent          | 69M        | 0.5%      | $21      |
| ScheduleWakeup | 47M        | 0.3%      | $14      |
| TaskCreate     | 25M        | 0.2%      | $8       |
| Grep           | 19M        | 0.1%      | $6       |
| Other          | 33M        | 0.2%      | $10      |
| **Subtotal**   | **2,689M** | **18.4%** | **$807** |

**Tool results** (returned output):

| Tool         | Tokens     | Share     | Cost       |
| ------------ | ---------: | --------: | ---------: |
| Read         | 3,042M     | 20.9%     | $913       |
| Bash         | 2,275M     | 15.6%     | $683       |
| Agent        | 117M       | 0.8%      | $35        |
| Grep         | 118M       | 0.8%      | $35        |
| Edit         | 95M        | 0.7%      | $28        |
| Glob         | 30M        | 0.2%      | $9         |
| Write        | 26M        | 0.2%      | $8         |
| WebFetch     | 20M        | 0.1%      | $6         |
| WebSearch    | 17M        | 0.1%      | $5         |
| Other        | 51M        | 0.3%      | $15        |
| **Subtotal** | **5,786M** | **39.7%** | **$1,736** |

Read results ($913) + Bash results ($683) = **$1,596**, 36.5% of all cache-read cost. Edit/Write/Grep add another $298 in call payloads.
