# Orchestration Reference

Full parallel subagent orchestration system documentation. Referenced from `AGENTS.md`.

## Parallel Subagent Orchestration

When a task involves **2+ independent work items** with no shared state or sequential dependencies, dispatch parallel subagents via the `task` tool in a single response.

### Condition: Use Parallel
<CONDITION_USE_PARALLEL>

All of these must hold:
- Items touch **different subsystems or files** (fixing one won't affect another)
- No **data dependency** between them (B doesn't need A's output)
- Each can be given a **self-contained prompt** (scope, goal, constraints, output format)
</CONDITION_USE_PARALLEL>

### Condition: Do NOT Use Parallel
<CONDITION_DO_NOT_USE_PARALLEL>

Any of these are true:
- Items share **state or overlapping files**
- One fix may **resolve others** (investigate together first)
- You need **full system context** first (explore before dispatching)
- Sequential dependency exists (B needs A's result)
</CONDITION_DO_NOT_USE_PARALLEL>

### Parallelization Metadata
<PARALLELIZATION_METADATA>

When dispatching parallel tasks, record the rationale in `WORKFLOW_STATE.md`'s TASKS section so the orchestrator (or later agents) can audit or retry with context.

Before dispatching any set of parallel tasks, verify all of these:

- [ ] No two tasks touch overlapping files or subsystems
- [ ] No inter-task data dependency (each prompt is self-contained)
- [ ] No shared mutable state between them
- [ ] Each prompt contains ALL context needed (subagents start empty)
</PARALLELIZATION_METADATA>

### Execution
<EXECUTION>

1. Identify independent domains and their `accuracy_risk` (low / medium / high)
2. Craft one self-contained prompt per domain (scope / goal / constraints / expected output)
3. Register each task in `WORKFLOW_STATE.md`'s TASKS section before dispatching
4. Dispatch **all** in the same response (one per response = sequential)
5. After all return: review summaries, check for conflicts, run full verification

Subagents do not inherit your session context — include all necessary context in each prompt.
</EXECUTION>

## Task State Machine
<TASK_STATE_MACHINE>

Every unit of work follows this lifecycle. State is tracked in `WORKFLOW_STATE.md`'s TASKS section.

```
backlog → ready → in_progress → review → done
            ↑          │
            │          ├→ blocked → ready  (unblocked)
            │          └→ blocked → cancelled
            │
            └──── review → in_progress      (rejected)
```

| State | Meaning |
|---|---|
| `backlog` | Not yet prioritized |
| `ready` | Prioritized, waiting for agent to pick up |
| `in_progress` | Agent is actively working |
| `review` | Work done, waiting for review pass |
| `done` | Completed (terminal) |
| `blocked` | Cannot proceed (record `blocked_reason`) |
| `cancelled` | Will not be done (terminal) |

### Rules

1. **One `in_progress` per orchestrator session** — only one task actively worked at a time (parallel tasks share a single time window but are grouped under one `in_progress` parent)
2. **Only orchestrator transitions states** — subagents read state and report results; the orchestrator moves the task to `review`/`done`/`blocked`/`cancelled`
3. **Review gate**: every task must pass through `review` before `done`. The reviewer subagent closes the gate.
4. **Rejected reviews** go back to `in_progress` with a note — not to `backlog`
5. **Blocked with reason**: set `blocked_reason` to explain. Use `blocked` for external blockers, not for "waiting for review" (that's `review`).
6. **Cancelled is terminal**: a cancelled task is never revived — spawn a new task if needed.
</TASK_STATE_MACHINE>

## Cost Tracking Per Run
<COST_TRACKING_PER_RUN>

Each attempt on a task records estimated cost in `WORKFLOW_STATE.md`'s RUN_LOG. This enables budget awareness without blocking execution.

### How it works

1. The orchestrator creates a run entry before dispatching (state: `running`)
2. After the subagent returns, the orchestrator fills in `finished_at`, `tokens`, and `cost_usd`
3. Cost is estimated as: `(input_tokens × input_price + output_tokens × output_price) / 1_000_000`
4. Use your provider's current per-token pricing for `input_price` and `output_price`

### Budget guardrails

- **Soft cap**: When cumulative cost exceeds `MAX_COST_PER_SESSION` (set in the project convention doc), flag in STATUS but continue
- **Hard cap**: When cumulative cost exceeds `HARD_CAP_USD`, stop dispatching new tasks and report to user
- Per-task cost is tracked regardless of budget — enables retrospective optimization
</COST_TRACKING_PER_RUN>

## Retry Policy
<RETRY_POLICY>

When a subagent fails, the orchestrator applies an error-aware retry policy before escalating to degradation.

### Error Classification
<ERROR_CLASSIFICATION>

| Error Type | Examples | Retry Strategy |
|---|---|---|
| **Transient** | Subagent timeout, network blip, tool briefly unavailable | Retry with exponential backoff + jitter (up to 2 attempts) |
| **Semantic** | Wrong output, hallucinated result, missed requirements | Re-prompt with refined, more specific context (1 attempt) |
| **Permanent** | Permission denied, missing tool, invalid input | Do not retry — escalate immediately |

</ERROR_CLASSIFICATION>

### Exponential Backoff with Jitter
<EXPONENTIAL_BACKOFF>

For transient failures, use this formula to prevent thundering herd when multiple subagents fail simultaneously:

```
base_delay × (2 ^ attempt) + random(0, base_delay)
```

- `base_delay`: 2 seconds
- `max_delay`: 30 seconds
- `max_attempts`: 2 (before falling to semantic retry or escalation)
- Jitter range: uniform random 0–100% of base_delay

</EXPONENTIAL_BACKOFF>

### Pre-flight Check
<PRE_FLIGHT_CHECK>

Before dispatching a subagent, verify:
- Task definition is self-contained (all context included in the prompt)
- Cost budget is not exhausted (see Cost Tracking)
- Any referenced file paths exist

</PRE_FLIGHT_CHECK>

### Retry Budget
<RETRY_BUDGET>

- **Per task**: max 2 retries across all error types
- **Per session**: retries count toward MAX_COST_PER_SESSION
- After exhausting retries: escalate for high `accuracy_risk` tasks, otherwise degrade

</RETRY_BUDGET>

</RETRY_POLICY>

## Handoff Protocol
<HANDOFF_PROTOCOL>

Versioned handoffs prevent context drift across multi-hop orchestration chains. Every handoff references its parent, so a receiving agent can reconstruct full context from `WORKFLOW_STATE.md` alone — no chat history needed.

### Protocol

1. **Before** starting work: read `WORKFLOW_STATE.md` for current phase, tasks, handoffs, and existing decisions
2. **After** completing work: update your section in `WORKFLOW_STATE.md`
3. **Create a handoff entry**: add a new row in the HANDOFFS log with:
   - `handoff_id`: sequential (`HND-NNN`)
   - `from_agent`: your agent type
   - `to_agent`: the receiving agent type
   - `parent_handoff`: the previous handoff id (or `—` if first)
   - `original_source`: the first handoff in the chain (copied from parent)
   - `context_summary`: concise context for the receiver
   - `status`: `pending` initially
4. The receiving agent updates status to `accepted`, then `completed` (or `rejected`)
5. On rejection (`rejected`): increment `version`, re-dispatch with same parent
6. Preserve existing content unless it is outdated or clearly incorrect

### Chain Example

```
orchestrator → explore:      HND-001 (original: HND-001, parent: —)
explore       → orchestrator: HND-002 (original: HND-001, parent: HND-001)
orchestrator → general:      HND-003 (original: HND-001, parent: HND-002)
general       → orchestrator: HND-004 (original: HND-001, parent: HND-003)
```

The receiving agent reads the handoff chain backwards from its entry to gather full context. This is the canonical workflow record. Do not rely on chat history.
</HANDOFF_PROTOCOL>

## Human Escalation Gate
<HUMAN_ESCALATION_GATE>

The orchestrator operates hands-off by default. Escalation to the user is reserved for situations where proceeding without guidance creates significant risk.

### When to escalate (AND all must hold)

- **Ambiguity is unresolvable**: multiple plausible interpretations and no heuristic can decide, AND
- **Revert cost is high**: the wrong choice would delete data, spend real money, or damage a production system, AND
- **All retries exhausted**: you have tried the most likely interpretation and it failed

### When NOT to escalate (these are NOT gates)

- Routine ambiguity (choose the most common interpretation and note the assumption)
- Missing preference on non-critical details (use defaults documented in AGENTS.md or the project convention doc)
- Multiple valid approaches (pick one, note the choice, move on)
- Simple confirmation ("should I proceed?") — assume yes and proceed

### Escalation format

When a gate does trigger, present a **single decision** with two options max, framed so the user can answer in one word or a short phrase. Never dump raw diagnostic output.

```
## ESCALATION
[<DECISION>]
- Option A: <brief>
- Option B: <brief>
Recommendation: <A or B>
</DECISION>
```

### One escalation per session

Once the user responds to an escalation, do not escalate again unless the situation fundamentally changes. Batch multiple decisions into one escalation message.
</HUMAN_ESCALATION_GATE>

## Graceful Degradation
<GRACEFUL_DEGRADATION>

When a subagent fails even after retries, the orchestrator degrades the task rather than failing the whole workflow. This preserves as much value as possible.

### Degradation Levels
<DEGRADATION_LEVELS>

| Level | Behavior | When Applied |
|---|---|---|
| **FULL** | Normal operation — dispatch specialist subagent | Default |
| **DEGRADED** | Use a general-purpose subagent (`@general`) instead of a specialist | Specialist unavailable or exhausted retries |
| **MINIMAL** | Skip the task, return a placeholder, continue | Non-critical task, partial result acceptable |
| **ESCALATE** | Stop and report to user | Critical task, no fallback available |

</DEGRADATION_LEVELS>

### Degradation Cascade
<DEGRADATION_CASCADE>

```
Subagent fails
  → Apply Retry Policy (up to 2 retries)
  → Still failing?
    → DEGRADED: dispatch @general with same self-contained prompt
    → Still failing?
      → Is task critical? (accuracy_risk = high)
        → Yes → ESCALATE (hand off to Human Escalation Gate)
        → No  → MINIMAL: mark as partial result, continue workflow
```

</DEGRADATION_CASCADE>

### Partial Results
<PARTIAL_RESULTS>

A task in MINIMAL degradation produces a partial result:
- `status`: `"partial"` in the result summary (not `"completed"`)
- `summary`: includes reason for failure so downstream agents know what's missing
- **Does NOT block** dependent tasks from proceeding
- Final user-facing output notes which parts are incomplete
- Partial results are recorded in RUN_LOG for audit

</PARTIAL_RESULTS>

</GRACEFUL_DEGRADATION>

## Orchestration Flow
<ORCHESTRATION_FLOW>

```
@orchestrator decomposes task
  │  registers tasks in TASKS section
  │  creates HND-001
  ├── @explore (research codebase in parallel)
  ├── @scout  (research dependencies in parallel)
  └── returns findings → HND-002
@orchestrator dispatches implementation
  │  sets cost run entries in RUN_LOG
  │  creates HND-003
  ├── @general  (implement module A)
  ├── @general  (implement module B)
  └── returns changes → HND-004
@orchestrator dispatches review
  │  tasks → review state
  │  creates HND-005
  ├── @reviewer (review all changes)
  ├── @tester   (run test suite)
  └── returns results → HND-006
@orchestrator integrates and verifies
  │  tasks → done
  │  creates HND-007
```
</ORCHESTRATION_FLOW>

## Fan-in Protocol
<FAN_IN_PROTOCOL>

After parallel subagents complete, the orchestrator collects and reconciles their results before integrating. Fan-in is the complement of fan-out — without it, parallel work produces disjoint outputs that may conflict silently.

### Subagent Result Contract
<SUBAGENT_RESULT_CONTRACT>

Every subagent MUST return its result in a structured format. The orchestrator enforces this contract — subagents that return unstructured output are treated as semantic failures (see Retry Policy).

Required fields:
- `status`: `"completed"` | `"partial"` | `"failed"`
- `summary`: 1–3 sentence summary of what was done
- `artifacts`: array of file paths produced (empty or omitted if none)
- `blockers`: array of strings describing anything that prevented completion (empty or omitted if none)

</SUBAGENT_RESULT_CONTRACT>

### Aggregation Steps
<AGGREGATION_STEPS>

1. **Collect** — wait for all subagents in the parallel batch to return (with timeout)
2. **Validate** — check each result against the contract above
3. **Resolve conflicts** — if two subagents modified overlapping files, flag for review
4. **Record partials** — any result with `status: "partial"` or `"failed"` is recorded in RUN_LOG
5. **Integrate** — merge accepted results into the project

</AGGREGATION_STEPS>

### Conflict Detection
<CONFLICT_DETECTION>

The orchestrator checks for:
- Overlapping file edits (same file modified by >1 subagent)
- Contradictory outputs (same logical change, different approaches)
- Missing dependencies (subagent B needed subagent A's output but B returned first)

When conflicts are found, the orchestrator flags them in REVIEW and does NOT auto-merge — the user or a reviewer agent resolves them.

</CONFLICT_DETECTION>

### Timeout Policy
<TIMEOUT_POLICY>

- Default timeout per subagent: 120 seconds (pass `timeout` in the task call for longer)
- Timed-out agents are treated as transient failures (see Retry Policy)
- Aggregation has its own timeout: `max(subagent_timeout) × number_of_parallel_tasks × 1.5`

</TIMEOUT_POLICY>

</FAN_IN_PROTOCOL>

## Provider Parallelism Limits
<PROVIDER_PARALLELISM_LIMITS>

| Provider | Max parallel tasks | Recommended starting point |
|---|---|---|
| Most providers | ~3–5 | 2 |

Beyond these ceilings you get timeouts, not speed. Start at 2, increase only after clean runs.
</PROVIDER_PARALLELISM_LIMITS>
