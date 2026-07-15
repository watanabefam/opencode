# Workflow State

<!--
  This file is the canonical record for multi-agent handoffs.
  Every agent reads it before starting work and updates its own
  section after completing.

  Sections:
    PLAN     — scope, acceptance criteria, implementation plan
    TASKS    — task registry with state machine
    RUN_LOG  — execution history with cost tracking
    HANDOFFS — versioned handoff records (parent references prevent drift)
    REVIEW   — review findings (PASS / items to address)
    TESTS    — test results (PASS / FAIL)
    STATUS   — current phase: planned | in-progress | review | done
-->

## PLAN
<PLAN>
  *Scope:* ...

  *Acceptance Criteria:*
  1. ...

  *Implementation Plan:* ...
</PLAN>

## TASKS
<TASKS>
  Task state machine. Each task follows this lifecycle:

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
  | `review` | Work done, waiting for review |
  | `done` | Completed (terminal) |
  | `blocked` | Cannot proceed (see `blocked_reason`) |
  | `cancelled` | Will not be done (terminal) |

  ### Task Schema

  Each task is a code-fenced JSON block with this schema:

  ```json
  {
    "id": "TASK-001",
    "title": "Brief description",
    "state": "backlog",
    "assigned_to": ["agent-type"],
    "priority": 0,
    "depends_on": [],
    "blocked_reason": null,
    "reviewer": "reviewer",
    "parallelize_with": [],
    "parallel_rationale": "Why parallelization is safe",
    "accuracy_risk": "low",
    "dependency_depth": 0,
    "created_by": "orchestrator",
    "created_at": "2026-01-01T00:00:00Z"
  }
  ```

  **Fields:**

  | Field | Type | Description |
  |---|---|---|
  | `id` | string | Unique identifier |
  | `title` | string | What needs to be done |
  | `state` | enum | See state machine above |
  | `assigned_to` | string[] | Subagent types assigned |
  | `priority` | int | 0 = highest |
  | `depends_on` | string[] | Task IDs this blocks on |
  | `blocked_reason` | string or null | Why blocked |
  | `reviewer` | string | Subagent type for review gate |
  | `parallelize_with` | string[] | Task IDs that can run in parallel |
  | `parallel_rationale` | string | Why this is safe to parallelize |
  | `accuracy_risk` | enum | `low` / `medium` / `high` — gates verification depth and degradation threshold |
  | `dependency_depth` | int | 0 = leaf, higher = more upstream deps |
  | `created_by` | string | Agent that created it |
  | `created_at` | ISO 8601 | When created |

  ### Task Register

  | ID | Title | State | Assigned | Pri | Parallel | Depends | Accuracy |
  |---|---|---|---|---|---|---|---|
  | TASK-001 | ... | backlog | @general | 0 | TASK-002 | — | low |
</TASKS>

## RUN_LOG
<RUN_LOG>
  Execution history. Each entry records one agent's attempt on a task.
  A task may have many runs (failed attempts don't fail the task).

  ### Run Schema

  ```json
  {
    "run_id": "TASK-001-1",
    "task_id": "TASK-001",
    "agent": "general",
    "state": "running",
    "attempt": 1,
    "started_at": "2026-01-01T00:00:00Z",
    "finished_at": null,
    "tokens": { "input": 0, "output": 0 },
    "cost_usd": 0.0,
    "result": null,
    "error": null,
    "artifacts": [],
    "retry_of": null,
    "degradation_level": "full",
    "partial_result": null
  }
  ```

  **Fields:**

  | Field | Type | Description |
  |---|---|---|
  | `run_id` | string | Unique per run (`{task_id}-{attempt}`) |
  | `task_id` | string | Task this run belongs to |
  | `agent` | string | Subagent type that executed |
  | `state` | enum | `running` / `completed` / `failed` / `cancelled` |
  | `attempt` | int | 1-based attempt number |
  | `started_at` | ISO 8601 | When the agent received the task |
  | `finished_at` | ISO 8601 or null | When the agent returned |
  | `tokens` | object | `{ input: int, output: int }` token counts |
  | `cost_usd` | number | Estimated cost of this run |
  | `result` | string or null | Summary of what was accomplished |
  | `error` | string or null | Error message if failed |
  | `artifacts` | string[] | Paths to files produced |
  | `retry_of` | string or null | Previous run_id this retries (chains retry history) |
  | `degradation_level` | enum | `full` / `degraded` / `minimal` — tracks how degraded this run was |
  | `partial_result` | string or null | Description of what was completed if task only partially succeeded |

  ### Run Log

  | Run | Task | Agent | State | Tokens (in/out) | Cost | Result |
  |---|---|---|---|---|---|---|
  | TASK-001-1 | TASK-001 | @general | running | 0/0 | $0.00 | — |
</RUN_LOG>

## HANDOFFS
<HANDOFFS>
  Versioned handoff records. Each handoff references its parent
  to prevent context drift across multi-hop orchestration chains.
  An agent receiving a handoff reads the parent chain to reconstruct
  full context without relying on chat history.

  ### Handoff Schema

  ```json
  {
    "handoff_id": "HND-003",
    "version": 1,
    "from_agent": "orchestrator",
    "to_agent": "general",
    "status": "completed",
    "context_summary": "Key context the receiving agent needs",
    "parent_handoff": "HND-002",
    "original_source": "HND-001",
    "created_at": "2026-01-01T00:00:00Z",
    "completed_at": "2026-01-01T00:05:00Z"
  }
  ```

  **Fields:**

  | Field | Type | Description |
  |---|---|---|
  | `handoff_id` | string | Unique identifier (`HND-NNN`) |
  | `version` | int | Monotonically increasing |
  | `from_agent` | string | Sender agent type |
  | `to_agent` | string | Receiver agent type |
  | `status` | enum | `pending` / `accepted` / `completed` / `rejected` |
  | `context_summary` | string | Concise context for the receiver |
  | `parent_handoff` | string or null | Previous handoff in the chain |
  | `original_source` | string or null | First handoff that started this chain |
  | `created_at` | ISO 8601 | When handoff was created |
  | `completed_at` | ISO 8601 or null | When handoff resolved |

  **Rules:**
  - `original_source` is set once on the first handoff and copied verbatim
  - `parent_handoff` always points to the immediate predecessor
  - Never rewrite a handoff; create a new entry
  - On rejection (`rejected`), increment `version` and retry with same parent

  ### Handoff Log

  | ID | Ver | From | To | Status | Parent | Original |
  |---|---|---|---|---|---|---|
  | HND-001 | 1 | orchestrator | explore | completed | — | HND-001 |
</HANDOFFS>

## REVIEW
<REVIEW>
  *PASS or list of findings with severity (critical / major / minor).*

  | Finding | Severity | File | Description |
  |---|---|---|---|
  | ... | major | src/foo.ts | Off-by-one in loop boundary |
</REVIEW>

## TESTS
<TESTS>
  *PASS or list of failures with command output.*

  ```
  $ npm test
  PASS  src/__tests__/foo.test.ts
  ```
</TESTS>

## STATUS
<STATUS>
  *Current phase: planned | in-progress | review | done*
</STATUS>
