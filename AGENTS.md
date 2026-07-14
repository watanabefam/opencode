# Parallel Subagent Orchestration

When a task involves **2+ independent work items** with no shared state or sequential dependencies, dispatch parallel subagents via the `task` tool in a single response.

## Condition: Use Parallel

All of these must hold:
- Items touch **different subsystems or files** (fixing one won't affect another)
- No **data dependency** between them (B doesn't need A's output)
- Each can be given a **self-contained prompt** (scope, goal, constraints, output format)

## Condition: Do NOT Use Parallel

Any of these are true:
- Items share **state or overlapping files**
- One fix may **resolve others** (investigate together first)
- You need **full system context** first (explore before dispatching)
- Sequential dependency exists (B needs A's result)

## Execution

1. Identify independent domains
2. Craft one self-contained prompt per domain (scope / goal / constraints / expected output)
3. Dispatch **all** in the same response (one per response = sequential)
4. After all return: review summaries, check for conflicts, run full verification

Subagents do not inherit your session context — include all necessary context in each prompt.

## Subagent Selection

| Agent | When to use | Can edit? |
|---|---|---|
| `@explore` | Read-only research, file searches, codebase understanding | No |
| `@general` | Full tool access, code changes, multi-step work | Yes |
| `@scout` | External docs and dependency research | No |
| `@reviewer` | Code review for correctness, security, regressions | No |
| `@tester` | Run project test suites and report results | No |
| `@orchestrator` | Decompose tasks and dispatch parallel workstreams | Yes |

## Handoff Protocol

1. **Before** starting work: read `WORKFLOW_STATE.md` for current phase and existing decisions
2. **After** completing work: update your section in `WORKFLOW_STATE.md` and append a handoff note
3. Preserve existing content unless it is outdated or clearly incorrect

`WORKFLOW_STATE.md` is the canonical workflow record. Do not rely on chat history.

## Orchestration Flow

```
@orchestrator decomposes task
  ├── @explore (research codebase in parallel)
  ├── @scout  (research dependencies in parallel)
  └── returns findings
@orchestrator dispatches implementation
  ├── @general  (implement module A)
  ├── @general  (implement module B)
  └── returns changes
@orchestrator dispatches review
  ├── @reviewer (review all changes)
  ├── @tester   (run test suite)
  └── returns results
@orchestrator integrates and verifies
```

## Provider Parallelism Limits

| Provider | Max parallel tasks | Recommended starting point |
|---|---|---|
| Claude Max20 | ~3 | 2 |
| GPT-5 / OpenAI | ~5 | 2 |
| Gemini Pro | ~5 | 2 |
| OpenRouter (most models) | varies | 2 |

Beyond these ceilings you get timeouts, not speed. Start at 2, increase only after clean runs.
