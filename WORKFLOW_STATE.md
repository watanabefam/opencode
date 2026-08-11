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
  *Phase:* IMPLEMENTATION — write verified recommendations + safe-adoption playbook into AGENTS.md and a project doc. Research rounds 1-2 + safe-integration research all DONE.

  *Scope:*
  1. Safe-integration research (how to adopt @playwright/cli, @playwright/mcp, skills, extensions WITHOUT breaking opencode config) — DONE (verified: bad MCP entry / malformed JSON crashes opencode; exact @playwright/mcp opencode config; skills CLI `-a opencode` support)
  2. Write compact "Browser Automation & AI Browser Tooling" section into AGENTS.md (always-loaded) + extend Gap Analysis instructions-file check
  3. Write docs/browser-automation-efficiency.md (deep playbook: recommendations, safe-adoption rules, tool playbooks, verification table, adoption checklist)
  4. Review gate (@reviewer) then close

  *Acceptance Criteria:*
  1. AGENTS.md section + doc written following hybrid-format convention (## + XML tags)
  2. Doc does NOT get added to opencode.json `instructions` (context bloat) — AGENTS.md pointer suffices; decision documented
  3. opencode.json itself unchanged/valid; no MCP enabled by default (opt-in documented)
  4. @reviewer passes the changes

  *Implementation Plan:*
  1. Register TASK-013 (done) / TASK-014 (write, orchestrator) / TASK-015 (review)
  2. Write AGENTS.md section + doc
  3. Dispatch @reviewer; integrate findings; close
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
  | TASK-001 | Scanner/installer script for token-optimization stack | done | @general | 0 | — | — | medium |
  | TASK-002 | Generic docs with decision rules + caveats | done | @general | 1 | — | TASK-001 | medium |
  | TASK-003 | README pointer + WORKFLOW_STATE tracking | done | @general | 2 | — | TASK-002 | low |
  | TASK-004 | Verification (syntax, dry-run, idempotent apply, index smoke) | done | @general | 0 | — | TASK-003 | medium |
  | TASK-005 | Research: Playwright/browser-automation efficiency best practices | done | @general | 0 | TASK-006, TASK-007 | — | medium |
  | TASK-006 | Research: third-party AI browsers & automation infra | done | @general | 0 | TASK-005, TASK-007 | — | medium |
  | TASK-007 | Research: Chrome Extensions for automation | done | @general | 0 | TASK-005, TASK-006 | — | medium |
  | TASK-008 | Synthesize findings into user-facing report | done | @orchestrator | 0 | — | TASK-005, TASK-006, TASK-007 | medium |
  | TASK-009 | Research: Playwright CLI (@playwright/cli) token-efficient automation | done | @general | 0 | TASK-010, TASK-011 | — | medium |
  | TASK-010 | Research: token-efficient AI browsers (Tappi, Agent Browser) + efficiency mechanisms | done | @general | 0 | TASK-009, TASK-011 | — | medium |
  | TASK-011 | Research: Chrome extensions round 2 (Playwright Extension, CRX, Playwriter) | done | @general | 0 | TASK-009, TASK-010 | — | medium |
  | TASK-012 | Synthesize round-2 findings into user-facing report | done | @orchestrator | 0 | — | TASK-009, TASK-010, TASK-011 | medium |
  | TASK-013 | Research safe opencode integration (MCP config, skills, crash rules) | done | @general | 0 | — | TASK-012 | high |
  | TASK-014 | Write AGENTS.md section + docs/browser-automation-efficiency.md | done | @orchestrator | 0 | — | TASK-013 | medium |
  | TASK-015 | Review gate: AGENTS.md section + doc | done | @reviewer | 0 | — | TASK-014 | medium |
  | TASK-016 | Machine adoption: install @playwright/cli (pinned) + skill + browser | done | @orchestrator | 0 | — | TASK-014 | medium |
  | TASK-017 | Token benchmark: CLI vs MCP on this machine | done | @orchestrator | 0 | — | TASK-016 | medium |
  | TASK-018 | Fix scout subagent: create global scout.md + correct 'built-in' doc claims | done | @orchestrator | 0 | — | — | medium |
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
  | TASK-001-1 | TASK-001 | @general | completed | 0/0 | $0.00 | scanner+installer built; fixed bash-3.2 (no assoc arrays), set -e traps, SIGPIPE, JSONC strip |
  | TASK-005-1 | TASK-005 | @general | completed | 0/0 | $0.00 | research complete: 8 domains covered, 10 ranked recommendations (parallelism, resource blocking, storageState, auto-wait, artifacts-on-retry) |
  | TASK-006-1 | TASK-006 | @general | completed | 0/0 | $0.00 | research complete: cloud browsers, AI agents (browser-use/Stagehand/Skyvern), stealth (Camoufox/rebrowser), scraping APIs + decision guide |
  | TASK-007-1 | TASK-007 | @general | completed | 0/0 | $0.00 | research complete: persistent-context loading, uBlock, MV3 custom extension snippet, caveats |
  | TASK-009-1 | TASK-009 | @general | completed | 0/0 | $0.00 | research complete: official CLI confirmed; 26K-vs-114K token claim UNVERIFIED; disk-based a11y snapshots + daemon + skills verified |
  | TASK-010-1 | TASK-010 | @general | completed | 0/0 | $0.00 | research complete: Tappi unverifiable (article deleted, no package); Agent Browser verified; a11y-tree/action-cache/schema-limits mechanisms validated |
  | TASK-011-1 | TASK-011 | @general | completed | 0/0 | $0.00 | research complete: Playwright Extension (official, MS), CRX (third-party), Playwriter (broadest permissions) all verified w/ security notes |
  | TASK-013-1 | TASK-013 | @general | completed | 0/0 | $0.00 | safe-integration research: verified @playwright/mcp opencode config, JSONC/MCP crash rules (issues #33845/#35954), skills CLI -a opencode, tool-collision & permission gotchas |
  | TASK-014-1 | TASK-014 | @orchestrator | completed | 0/0 | $0.00 | wrote AGENTS.md section + docs/browser-automation-efficiency.md; applied all 5 reviewer fixes; gap check re-verified PASS |
  | TASK-016-1 | TASK-016 | @orchestrator | completed | 0/0 | $0.00 | machine adoption: `npm install -g @playwright/cli@0.1.17` (pinned) + `install --skills` → .claude/skills/playwright-cli (project-scoped, opencode-discovered) + `install-browser chromium` (headless shell v1232); smoke test OK (daemon + a11y snapshot as file link); .gitignore updated for .claude/ + .playwright-cli/ |
  | TASK-017-1 | TASK-017 | @orchestrator | completed | 0/0 | $0.00 | benchmark (example.com, this machine): CLI open stdout 267 B (~66 tok), snapshot file 315 B (~78 tok), eval output 336 B (~84 tok); MCP inline snapshot NOT measurable (live profile-lock between the two playwright MCP servers — confirms --isolated advice); MCP est ~= a11y content size, scales with page. Method: bytes/4 heuristic. Does NOT validate the 26K/114K claim — validates mechanism (file-link vs inline tree). Committed ea57ca3. |
  | RQ-ORCA-1 | RQ-ORCA | @general | completed | 0/0 | $0.00 | OrcaRouter verification (user query): real LLM routing gateway (LiteLLM/OpenRouter class, SaaS + MIT self-hosted Lite). Cuts COST, not tokens. 75.5% accuracy arXiv-backed (arXiv:2605.30736, self-submitted, paper says ranked 2nd on RouterArena — homepage omits). "40% lower cost"/"-90% cache" = unverified marketing. Verdict: NOT a token-savings measure; do not add to doc unless a cost-savings section is created (cite only arXiv claim; benchmark before quoting figures). |
  | TASK-018-1 | TASK-018 | @orchestrator | completed | 0/0 | $0.00 | root cause: scout is NOT an opencode built-in (@opencode-ai/cli 1.17.8 ships build/plan/general/explore + hidden compaction/title/summary; live agent_list shows no scout) and no scout.md existed in any agent dir → orchestrator task-dispatch of @scout fails in every project that attempts it ("some projects" = projects whose orchestrator actually tried external-dependency research). Fix: created ~/.config/opencode/agents/scout.md (mode: subagent; read/grep/glob + webfetch/websearch allow; write/edit/task deny; bash scoped to git clone/-C/ls-remote + npm view/info/pack + curl/wget; clones restricted to managed cache) so it applies globally (agent discovery: project .opencode/agents/ → ~/.config/opencode/agents/; no project overrides scout). Corrected the false "Built-in (available without config)" claim in 3 orchestrator.md files (global, opencode, n8n) — scout moved under Custom subagents with accurate permissions. All orchestrator task allowlists already had "scout": allow, so no per-project config change needed. Live-server registration unverified this session: `opencode web` (PID 1315, port 4096) saturated at ~80% CPU (browser-automation load) → MCP agent_list + HTTP both time out. Verify after server restarts / next session: scout should appear in agent list and task tool. |
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
  | HND-002 | 1 | orchestrator | general | completed | — | HND-002 |
  | HND-003 | 1 | orchestrator | general | completed | — | HND-003 |
  | HND-004 | 1 | orchestrator | general | completed | — | HND-004 |
  | HND-005 | 1 | orchestrator | reviewer | completed | — | HND-005 |
</HANDOFFS>

## REVIEW
<REVIEW>
  *Browser-automation deliverables — reviewer verdict: CONCERNS (no criticals, 1 major + 4 minor). All resolved & re-verified:*

  | Finding (from @reviewer) | Severity | Resolution |
  |---|---|---|
  | Gap Analysis instructions-files check used bare `browser-automation-efficiency.md` (file lives in `docs/`) → check could never pass | major | Added `docs/` prefix; check re-run → PASS |
  | AGENTS.md MCP example used `@playwright/mcp@latest` while rule 6 + doc mandate pinning | minor | Example now `@playwright/mcp@<pinned>` with pointer to doc §2.2; doc snippet uses `<pinned-version>` placeholder (no unverified version cited) |
  | Crash issue attribution lumped (#33845+#35954 for both causes) | minor | Matched doc attribution: #35954 = malformed JSON, #33845 = bad MCP entry |
  | `@playwright/cli` "Apache-2.0" license claim not in verification table | minor | Added license to verified row in Part 5 table (npm metadata) |
  | "unknown frontmatter fields are ignored" behavioral claim unverified | minor | Hedged: "ignored by current opencode versions — re-verify after upgrades" |
  | Hybrid-format compliance, config-safety rules, factual verification split, security guidance | PASS (no change) | — |
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
  *Current phase: done — browser-automation efficiency research + adoption docs complete (TASK-005..016 closed).
  Scout fix (TASK-018, DONE): created global ~/.config/opencode/agents/scout.md + corrected false "built-in" claims in
  orchestrator.md (global + opencode + n8n). OPEN ITEM: confirm scout registers on the running server after restart —
  `opencode web` (PID 1315) was saturated (~80% CPU) so live agent_list verification timed out; scout should appear in
  `opencode_agent_list` / the task tool in the next session in every project.
  Rounds 1-2 research verified; recommendations + safe-adoption rules written into AGENTS.md (always-loaded) and
  docs/browser-automation-efficiency.md (playbook, verification table, checklist); reviewer findings all resolved;
  gap check passes; opencode.json untouched/valid. THIS machine adopted @playwright/cli 0.1.17 (current @latest at install;
  policy = track, don't freeze — keep current, record versions, smoke-test after upgrades, per doc §2.6) + skill +
  chromium headless shell v1232; smoke test OK. Committed ea57ca3 (AGENTS.md, docs/browser-automation-efficiency.md,
  .gitignore, WORKFLOW_STATE.md). Token benchmark recorded (TASK-017): CLI immediate context ~66 tok/task on example.com
  vs MCP returning the a11y tree inline (unmeasured this session — live profile-lock between the two playwright MCP servers
  confirms the --isolated advice; does NOT validate the 26K/114K marketing claim). Uncommitted leftovers: README.md +
  .DS_Store (pre-existing), scripts/ + docs/token-optimization.md (prior task). Next machine: gap analysis + Part 6 checklist.*
  Advisory (2026-08-03): OrcaRouter evaluated against docs/token-optimization.md ("token savings measures").
  Verdict: NOT a token-saving layer (cuts cost-per-token, not token count; savings figures unverified marketing —
  violates the doc's own Honest Caveats rule). Added one-line caveat (routing gateways) beside the existing
  "cheap models" provider lever. See RUN_LOG RQ-ORCA-1.*
  Config change (2026-08-03): global opencode.jsonc `playwright` MCP server switched `--user-data-dir=<shared profile>` →
  `--isolated` (temp profile) to fix the persistent-profile lock between the two playwright servers (TASK-017 finding).
  Backup: ~/.config/opencode/opencode.jsonc.bak.20260803064906. JSONC validated. Takes effect on next opencode restart;
  current session's playwright servers still run old config. `playwright-tabbed` unchanged (no --isolated support; keeps
  persistent profile). Optional follow-up: pin @playwright/mcp version.
</STATUS>
