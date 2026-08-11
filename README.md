# OpenCode Parallel Subagent Orchestration

<SUBTITLE>
  Multi-agent workflow system for OpenCode where a primary orchestrator
  decomposes tasks and dispatches independent workstreams to specialist
  subagents running concurrently with fresh context.
</SUBTITLE>

---

## Quick Start

<QUICK_START>
  ```
  # 1. Open a session in this project directory
  # 2. The orchestrator loads automatically (default_agent in opencode.json)
  # 3. Ask for something complex — the orchestrator decomposes and dispatches
  #    Example: "Review this project structure and list all agents available"

  # For setup on a new project:
  #   - Create AGENTS.md with orchestration rules (use .opencode/agents/orchestrator.md as reference)
  #   - Define subagents (reviewer, tester, orchestrator) in .opencode/agents/
  #   - Create WORKFLOW_STATE.md for handoff coordination
  #   - Configure opencode.json with default_agent and permissions
  ```
</QUICK_START>

---

## File Overview

<FILE_OVERVIEW>
  | File | Purpose | Read this if you... |
  |---|---|---|
  | `AGENTS.md` | Canonical orchestration rules — parallel conditions, state machine, cost tracking, handoff protocol, escalation gates | ...are an agent and need to know how to dispatch, review, or hand off work |
  | `WORKFLOW_STATE.md` | Runtime state — task registry, run log, handoff records, review findings | ...are an agent and need current context before starting work |
  | `.opencode/agents/orchestrator.md` | Orchestrator agent definition — runtime rules, state machine, handoff protocol, cost tracking, retry/degradation | ...are writing or updating the orchestrator agent |
  | `opencode.json` | OpenCode project config — loads AGENTS.md as instructions, sets default_agent to orchestrator | ...are configuring the project entry point |
  | `hybrid-format-convention.md` | Hybrid markdown + XML tag format for cross-model compatibility | ...are writing or editing system prompts |
  | `workspace-convention.md` | Workspace layout for project outputs | ...are managing generated artifacts across projects |
</FILE_OVERVIEW>

---

## Token Optimization Pipeline

<TOKEN_OPTIMIZATION>
  Cut token spend in OpenCode on **any** machine with a scan-first setup
  pipeline. The script detects the machine (OS, arch, RAM, disk, tools,
  agents, LLM provider) and applies only the layers that machine can support —
  nothing is hardcoded to a specific host.

  ```
  # 1. Scan + see what this machine supports (no changes):
  ./scripts/setup-token-stack.sh --projects ~/code

  # 2. Apply the suitable layers (idempotent, backs up config first):
  ./scripts/setup-token-stack.sh --apply

  # 3. Index the repos you actually work on:
  ./scripts/setup-token-stack.sh --index ~/code/app ~/code/lib
  ```

  Layers: built-in compaction (always) → Codebase Memory MCP + rtk (Tier 1,
  what `--apply` installs) → Token Optimizer MCP (Tier 2, manual, RAM >= 16 GB
  only) → caveman/Context7 (Tier 3, manual, optional).
  Full decision rules and honest caveats: `docs/token-optimization.md`.
</TOKEN_OPTIMIZATION>

---

## Key Concepts

<KEY_CONCEPTS>

  ### Parallel Dispatch
  <PARALLEL_DISPATCH>
    - Dispatch **all** independent subagents in the same response (one `task` call per response = sequential)
    - Each prompt must be self-contained — subagents start with zero session history
    - Before dispatching: verify no overlapping files, no data dependency, no shared state
    - Record parallelization rationale in WORKFLOW_STATE.md's TASKS section
  </PARALLEL_DISPATCH>

  ### Task State Machine
  <TASK_STATE_MACHINE>
    ```
    backlog → ready → in_progress → review → done
                ↑          │
                │          ├→ blocked → ready
                │          └→ blocked → cancelled
                │
                └──── review → in_progress  (rejected)
    ```
    - Only the orchestrator transitions states
    - Every task passes through `review` before `done`
    - Cancelled is terminal — never revived
  </TASK_STATE_MACHINE>

  ### Cost Tracking
  <COST_TRACKING>
    - Each run records estimated token count + USD cost in RUN_LOG
    - Soft cap: flag when cumulative cost exceeds MAX_COST_PER_SESSION
    - Hard cap: stop dispatching when cumulative cost exceeds HARD_CAP_USD
    - Per-task cost tracked regardless of budget (retrospective optimization)
  </COST_TRACKING>

  ### Handoff Protocol
  <HANDOFF_PROTOCOL>
    - Every handoff gets a sequential HND-NNN id referencing its parent
    - Chained: HND-001 → HND-002 → HND-003 (parent_handoff tracks back)
    - Append-only — never rewrite a handoff entry
    - On rejection, increment version and retry with same parent
    - WORKFLOW_STATE.md is the source of truth, not chat history
  </HANDOFF_PROTOCOL>

  ### Escalation Gate
  <ESCALATION_GATE>
    - **High threshold** — the orchestrator is hands-off by default
    - Escalation requires ALL three:
      1. Unresolvable ambiguity (no heuristic can decide)
      2. High revert cost (data loss, real money, production damage)
      3. All retries exhausted
    - Routine ambiguity → pick the common interpretation, note assumption, proceed
    - One escalation per session; batch multiple decisions into one message
  </ESCALATION_GATE>

</KEY_CONCEPTS>

---

## Agent Roles

<AGENT_ROLES>

  | Agent | Type | Role | Can edit? |
  |---|---|---|---|
  | `@orchestrator` | primary | Decomposes tasks, dispatches parallel subagents, tracks state | Yes |
  | `@explore` | subagent | Read-only codebase research, file searches | No |
  | `@general` | subagent | Implementation work, multi-step changes | Yes |
  | `@scout` | subagent | External dependency research | No |
  | `@reviewer` | subagent | Code review (correctness, security, regressions) | No |
  | `@tester` | subagent | Run test suites and report results | No |

</AGENT_ROLES>

---

## Workflow

<WORKFLOW>
  ```
  @orchestrator decomposes task
    │  registers tasks in TASKS
    │  creates handoff HND-001
    ├── @explore (read-only research)
    ├── @scout   (dependency research)
    └── returns findings → HND-002
  @orchestrator dispatches implementation
    │  sets cost entries in RUN_LOG
    │  creates handoff HND-003
    ├── @general (module A)
    ├── @general (module B)
    └── returns changes → HND-004
  @orchestrator dispatches review
    │  tasks → review state
    │  creates handoff HND-005
    ├── @reviewer (review changes)
    ├── @tester   (run tests)
    └── returns results → HND-006
  @orchestrator integrates and verifies
    │  tasks → done
    │  creates handoff HND-007
  ```
</WORKFLOW>

---

## For AI Agents Reading This

<FOR_AGENTS>
  - **Start here** if you need an overview of the system. Then read `AGENTS.md` for the full orchestration rules.
  - **Before any work**: read `WORKFLOW_STATE.md` for current phase, tasks, handoffs, and existing decisions.
  - **After your work**: update your section in `WORKFLOW_STATE.md` and create a handoff entry in the HANDOFFS log.
  - **Do not rely on chat history** — every agent gets fresh context. All state lives in `WORKFLOW_STATE.md`.
  - **Parallelism rule**: dispatch all independent tasks in the same response. One `task` call per response = sequential.
  - **Escalation rule**: proceed by default. Only escalate to the user for high-stakes ambiguity after retries.
  - **Cost awareness**: runs are tracked in RUN_LOG. Stay within guardrails set in the orchestrator agent.
</FOR_AGENTS>

---

## For Humans

<FOR_HUMANS>
  - **Ask for complex work** and the orchestrator handles decomposition. Try: "Review the project and summarize the architecture" or "Find any security issues in the codebase."
  - **To follow along**: check `WORKFLOW_STATE.md` — it shows current tasks, completed runs, and the handoff chain.
  - **Budget awareness**: `MAX_COST_PER_SESSION` and `HARD_CAP_USD` control costs. Set them in the project's convention doc. The RUN_LOG tracks spend per session.
  - **Customizing agents**: add new agents under `.opencode/agents/` and update the orchestrator's `permission.task` allowlist.
  - **Concurrency limits**: most providers cap parallel requests. Start with 2 parallel tasks, increase only after clean runs.
  - **Debugging handoffs**: the HANDOFFS log in `WORKFLOW_STATE.md` shows every agent-to-agent transition with timestamps. Rejected handoffs show the version increment.
  - **Adding this to another project**: copy the `.opencode/agents/` directory and `AGENTS.md`, create `WORKFLOW_STATE.md`, and set `default_agent: orchestrator` in `opencode.json`. The orchestrator agent carries all runtime rules.
</FOR_HUMANS>

---

## License

<LICENSE>
  This is a configuration template for OpenCode. Use freely, adapt
  to your project's needs. Attribution is appreciated but not required.
</LICENSE>
