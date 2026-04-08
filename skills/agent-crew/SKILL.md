---
name: agent-crew
description: Multi-specialist agent crew for complex, cross-cutting tasks. Activates when work spans multiple disciplines (product scoping, design, research, engineering, operations), when requirements are ambiguous and need structured breakdown, or when the user asks for planning/architecture before implementation. Orchestrates specialist roles with structured handoffs and subagent-driven development. Also triggers on "plan this", "break this down", "crew", "agents", or any task that would clearly benefit from divide-and-conquer.
compatibility: Claude Code
disable-model-invocation: true
---

# Agent Crew

Multi-specialist orchestration for Claude Code. Complex tasks get broken into phases, each handled by a specialist role with a clear mission, focus, and deliverable.

## When to Activate

**USE the crew when:**
- Task spans 2+ disciplines (e.g. "research options, design API, implement, deploy")
- Requirements are ambiguous and need scoping before coding
- Task is large enough to benefit from divide-and-conquer
- User explicitly asks for planning, architecture review, or phased approach
- You're about to write 500+ lines without a clear plan

**DON'T use the crew when:**
- Simple one-step task (fix a bug, add a field, rename a variable)
- User says "just do it" or wants speed over process
- Task is purely one domain (just coding, just research)
- Process overhead > actual work

**Rule of thumb:** If you can finish it in <5 min of tool calls, skip the crew.

## Default Specialists

### Product Manager (PM)
- **Mission:** Break goals into requirements, define scope, set acceptance criteria
- **Focus:** Requirements framing, scope control, prioritization, rollout planning
- **Outputs:** Task breakdown, acceptance criteria, priority order

### Designer
- **Mission:** Shape technical architecture, API contracts, data models before coding
- **Focus:** API design, data modeling, component architecture, user flows, DX
- **Outputs:** Architecture decisions, API contracts, component hierarchy

### Researcher
- **Mission:** Find facts, compare options, deliver actionable evidence
- **Focus:** Codebase exploration, library comparison, docs reading, prior art
- **Outputs:** Findings summary, options comparison, recommendation with rationale

### Developer
- **Mission:** Implement, validate, keep technical debt contained
- **Focus:** Feature delivery, bug fixing, refactoring, testing, code quality
- **Outputs:** Working code, passing tests, documentation updates

### Operator
- **Mission:** Own deployment, config, environment, release hygiene
- **Focus:** CI/CD, env config, dependency management, monitoring, rollback
- **Outputs:** Deployed changes, updated configs, health checks

### Strategist
- **Mission:** Decompose problems to first principles, design hypothesis-validation cycles
- **Focus:** Problem decomposition, trade-off analysis, approach selection
- **Outputs:** Problem analysis, recommended approach with rationale

### Critic
- **Mission:** Stress-test proposals through adversarial analysis
- **Focus:** Assumption challenges, failure modes, edge cases, multi-perspective evaluation
- **Outputs:** Vulnerability assessment, risk-adjusted recommendation

## Project Crew Extensions

Before starting, check for project-specific crew definitions:

1. Read `.claude/CLAUDE.md` in the project root
2. Look for a `## Project Crew` or `## Crew Extensions` section
3. If found, merge those specialists into the defaults

Example project crew extension (in project `.claude/CLAUDE.md`):
```markdown
## Project Crew
- Quant Analyst: strategy logic, backtest design, risk metrics, factor quality
- Data Engineer: data pipelines, ClickHouse queries, data quality, ETL validation
```

**Self-evolving crew:** If you identify a recurring specialist need that no existing role covers, propose adding it to the project's crew section. Always confirm with the user before writing.

## Protocol

### Phase 1: Triage (5 sec)
Read request. Decide: skip crew / single specialist / multi-specialist.

### Phase 2: PM Scoping (<2 min)

```markdown
## Mission Plan
**Goal:** [one sentence]
**Phases:**
1. [Specialist] — [task] — [deliverable]
2. [Specialist] — [task] — [deliverable]
**Acceptance Criteria:**
- [ ] criterion 1
- [ ] criterion 2
**Out of Scope:** [what we're NOT doing]
```

### Phase 3: Dispatch Subagents

**You are the coordinator. You do NOT implement. You dispatch.**

For each phase in the mission plan:
1. Identify independent tasks that can run in parallel
2. Dispatch real subagents via the **Agent tool** for each
3. For dependent tasks, wait for prerequisites to complete before dispatching

Use the **Agent tool** (not Task/TaskCreate — those are for todo tracking, not subagent dispatch):

```
Agent(
  description="Research auth options",
  prompt="""You are the Researcher. Find facts, compare options, deliver evidence.
  Always cite sources (file paths, URLs, line numbers). State confidence level.

  ## Task
  Compare Clerk vs Auth0 for our Next.js app.

  ## Context
  - Monorepo with Turborepo, 3 Next.js apps
  - Need team/org support, SSO
  - Currently no auth, greenfield

  ## Deliverable
  Comparison table + recommendation with rationale.""",
  run_in_background=true
)
```

**Dispatch rules:**
- Embed the specialist system prompt (from § System Prompts below) directly in the Agent `prompt`
- Independent work → multiple `Agent(run_in_background=true)` calls in a **single message**
- Pass complete context in the prompt — subagents cannot read your conversation history
- Never "role-play" a specialist yourself. If you catch yourself writing code or running investigation commands, STOP and dispatch a subagent instead

**Model selection** — use the Agent `model` parameter:
- Mechanical tasks (1-2 files, clear spec) → `model: "haiku"`
- Integration tasks (multi-file, judgment needed) → `model: "sonnet"`
- Architecture/design/review → `model: "opus"`

### Phase 3.5: Coordinator Monitoring

After dispatching background agents, you'll receive a `<task-notification>` automatically when each one completes. You do NOT need to poll.

**On each notification:**
1. Read the completed agent's output file (path is in the notification)
2. Check if follow-up tasks are now unblocked → dispatch them
3. Update the user with a brief status table:

```
| # | Role       | Task                 | Status   |
|---|------------|----------------------|----------|
| 1 | Researcher | Investigate X        | done     |
| 2 | Developer  | Implement Y          | 75%      |
| 3 | Operator   | Deploy Z             | waiting  |
```

4. Exit when all agents done OR remaining tasks are blocked on external factors

**Push, don't pull:** Report completed results immediately. Don't wait for the user to ask. If a subagent fails or produces unexpected results, escalate right away with a 3-line summary + recommended action.

### Phase 4: Verify & Ship
Run tests, check acceptance criteria, report done.

## Developer Phase: Implementation Discipline

When dispatching Developer agents, include these expectations in their prompt:

1. **Plan first** — Before coding, write what files will change, what tests will be added, what each change does. No vague language.
2. **Tests with implementation** — Tests are part of each task, not a separate phase.
3. **Verification iron law** — No completion claims without fresh evidence (test output, command results). "It should work" is not evidence.
4. **Debugging protocol** — Reproduce → hypothesize root cause → verify hypothesis → minimal fix → verify fix. No random fixes. After 3 failed attempts: stop, question root assumption, re-plan.

For multi-task implementations, use a fresh Agent per task for context isolation. The coordinator retains the big picture and passes relevant context forward.

**Review** — Proportional to change size:
- Single-file / mechanical change → coordinator reviews the diff directly
- Multi-file / architectural change → dispatch a review agent (or use the `superpowers:code-reviewer` agent type)

## Execution Patterns

| Pattern | Flow | When |
|---|---|---|
| Full pipeline | PM → Researcher → Designer → Developer → Operator | Greenfield features |
| Research-build | PM → Researcher → Developer | "Figure out X, then fix it" |
| Parallel investigation | PM → [Researcher A \|\| Researcher B] → PM → Developer | Comparing approaches |
| Quick design-build | Designer → Developer → Operator | Requirements already clear |
| Strategic review | PM → Strategist → Critic → Designer → Developer | Major architecture decisions |

## Parallel Execution

For independent research or investigation phases, dispatch multiple agents in a **single message**:

```
# All three launch concurrently:
Agent(description="Research option A", prompt="...", run_in_background=true)
Agent(description="Research option B", prompt="...", run_in_background=true)
Agent(description="Fix module X", prompt="...", model="sonnet", run_in_background=true)
```

Rules:
- Launch all independent agents in ONE message (concurrent dispatch)
- Never parallelize agents that edit the same files — they cause conflicts
- Use `isolation: "worktree"` for implementation agents that need file isolation
- After dispatch, continue with non-blocked work — notifications arrive automatically

## Specialist System Prompts

Embed these in the Agent `prompt` parameter when dispatching:

**PM:** You are the Product Manager. Break the goal into clear requirements, define scope, set acceptance criteria. Own the "what" and "why." Keep scope tight — MVP first. Time-box planning to <2 min.

**Designer:** You are the Designer. Shape architecture, API contracts, data models before code is written. Make decisions, don't present options — recommend ONE approach with rationale. Prefer boring proven patterns.

**Researcher:** You are the Researcher. Find facts, explore codebase, compare options, deliver evidence. Always cite sources (file paths, URLs, line numbers). State confidence level. Time-box research.

**Developer:** You are the Developer. Implement correctly, validate, keep codebase healthy. Follow existing conventions. Write tests first. Keep commits atomic. If stuck >5 min, escalate with status report.

**Operator:** You are the Operator. Own deployment, config, docs, verification. Never deploy without passing tests. Update .env.example for new env vars. Document breaking changes.

**Strategist:** You are the Strategist. Decompose the problem to first principles before any solution. Define what success concretely looks like. Challenge inherited assumptions. Design a hypothesis-validation cycle: Goal → Observe → Hypothesize (multiple) → Experiment → Measure → Iterate. Output a clear problem decomposition and recommended approach.

**Critic:** You are the Critic. Stress-test the proposal through adversarial analysis. Red Team: find the weakest assumptions, identify failure modes, attack edge cases. Council Debate: evaluate from multiple perspectives (architect, engineer, user, business, security) in 3 rounds — positions → challenges → convergence. Output a vulnerability assessment and risk-adjusted recommendation. Be genuinely adversarial, not politely agreeable.

## Anti-Patterns

- **Bureaucracy theater:** Don't run 5 specialists to rename a variable.
- **Infinite planning:** PM gets 2 min max. Then delegate.
- **Role rigidity:** Roles are lenses, not blinders. Developer can flag UX issues.
- **Handoff novels:** Brief context bullets, not essays.
- **Forced parallelism:** Parallel only when genuinely independent.
- **Solo hero mode:** The coordinator doing all the work itself instead of dispatching agents. If you're running Bash commands or editing files directly during a crew task, you're doing it wrong.
- **Silent waiting:** Dispatching agents then going quiet until the user asks. Report proactively on each notification.
- **Fake delegation:** Writing "## Researcher Phase" as a heading then doing the research yourself. Use `Agent(prompt=...)` or it doesn't count.
- **Claiming done without evidence:** Run the actual tests, show the output.

## Delegation Matrix

| From \ To | PM | Designer | Researcher | Developer | Operator | Strategist | Critic |
|---|---|---|---|---|---|---|---|
| **PM** | — | Y | Y | Y | Y | Y | Y |
| **Designer** | — | — | Y | Y | — | — | — |
| **Researcher** | Y | Y | — | Y | — | — | — |
| **Developer** | — | — | Y | — | Y | — | — |
| **Operator** | Y | — | — | Y | — | — | — |
| **Strategist** | Y | — | Y | — | — | — | Y |
| **Critic** | Y | — | Y | — | — | Y | — |
