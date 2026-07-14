
<GOAL>
  ; Configure OpenCode with custom agents, scoped permissions, and parallel
  ; subagent orchestration. Enables multi-agent workflows where a primary
  ; orchestrator delegates independent tasks to specialist subagents running
  ; concurrently with fresh context — preventing context pollution, controlling
  ; costs, and maintaining quality through review gates.
</GOAL>

<PREREQUISITES>
  ; OpenCode installed and running (terminal or desktop).
  ; Basic familiarity with opencode agents, config files, and the `@` mention
  ; system for invoking subagents.
  ; A text editor to create `.md` files.
</PREREQUISITES>

<VARIABLES>
  ; Paths — adjust if your config lives elsewhere.
  PROJECT_ROOT:             /path/to/your/project
  AGENTS_MD:                ${PROJECT_ROOT}/AGENTS.md
  LOCAL_AGENTS_DIR:         ${PROJECT_ROOT}/.opencode/agents/
  GLOBAL_AGENTS_DIR:        ~/.config/opencode/agents/

  ; Agent definitions — filenames become agent names.
  AGENT_REVIEWER:           reviewer
  AGENT_TESTER:             tester
  AGENT_ORCHESTRATOR:       orchestrator

  ; Shared handoff file — every agent reads before work, writes after.
  HANDOFF_FILE:             WORKFLOW_STATE.md

  ; Models — adjust per your provider.
  MODEL_REASONING:          (your strongest model, e.g. anthropic/claude-sonnet-4-20250514)
  MODEL_FAST:               (your cheapest model, e.g. anthropic/claude-haiku-4-20250514)

  ; Parallelism — start at 2, increase only after clean runs.
  MAX_CONCURRENT_TASKS:     2
</VARIABLES>

<IDEMPOTENT>
  ; This document is designed to be run on a project that may already have
  ; some elements in place. Each step has a GATE — a quick check to see if
  ; that step is already satisfied. Steps whose gate passes are SKIPPED.
  ; Only steps whose gate FAILS are APPLIED.
  ;
  ; GATE results:
  ;   PASS = already configured → skip the step
  ;   FAIL = not configured → apply the step
</IDEMPOTENT>

<GAP_ANALYSIS>
  ; Run this block first to discover which steps are needed on the
  ; current project. Output: a table of step + gate status (PASS/FAIL).

  <CHECKS>
    AGENTS.md exists:              test -f ${AGENTS_MD};
    AGENTS.md has parallel rules:  test -f ${AGENTS_MD} && grep -qi "parallel" ${AGENTS_MD};
    Local agents dir:              test -d ${LOCAL_AGENTS_DIR};
    Reviewer agent:                test -f ${LOCAL_AGENTS_DIR}${AGENT_REVIEWER}.md;
    Tester agent:                  test -f ${LOCAL_AGENTS_DIR}${AGENT_TESTER}.md;
    Orchestrator agent:            test -f ${LOCAL_AGENTS_DIR}${AGENT_ORCHESTRATOR}.md;
    Handoff file exists:           test -f ${PROJECT_ROOT}/${HANDOFF_FILE};
    opencode.json has agents:      test -f ${PROJECT_ROOT}/opencode.json && grep -q "agent" ${PROJECT_ROOT}/opencode.json;
  </CHECKS>

  SUMMARY_TEMPLATE:
    ; STEP                         GATE      ACTION
    ; STEP_1_AGENTS_MD             PASS/FAIL skip / create AGENTS.md
    ; STEP_2_AGENTS_DIR            PASS/FAIL skip / mkdir .opencode/agents/
    ; STEP_3_REVIEWER              PASS/FAIL skip / create reviewer.md
    ; STEP_4_TESTER                PASS/FAIL skip / create tester.md
    ; STEP_5_ORCHESTRATOR          PASS/FAIL skip / create orchestrator.md
    ; STEP_6_HANDOFF               PASS/FAIL skip / create WORKFLOW_STATE.md
    ; STEP_7_PERMISSIONS           PASS/FAIL skip / wire task permissions
    ; STEP_8_VERIFY                PASS/FAIL skip / dry-run test
</GAP_ANALYSIS>

<STEPS>

  <!-- ──────────────── STEP 1 — Create AGENTS.md ──────────────── -->

  <STEP_1_AGENTS_MD>
    GATE:   test -f ${AGENTS_MD} && grep -q "dispatch parallel subagents" ${AGENTS_MD};
    IF_PASS: skip; (AGENTS.md with parallel rules already exists)
    IF_FAIL:
      INSTRUCT:
        Create ${AGENTS_MD} with the Parallel Subagent Orchestration rules.
        See the accompanying AGENTS.md file in this repo for the full template.
        It documents:
          - Conditions for parallel vs sequential dispatch
          - Execution protocol (self-contained prompts, dispatch all at once)
          - Subagent selection (explore / general / scout)
          - Handoff via WORKFLOW_STATE.md
      VERIFY: test -f ${AGENTS_MD} && grep -q "dispatch parallel subagents" ${AGENTS_MD};
  </STEP_1_AGENTS_MD>

  <!-- ──────────────── STEP 2 — Create agents directory ──────────────── -->

  <STEP_2_AGENTS_DIR>
    GATE:   test -d ${LOCAL_AGENTS_DIR};
    IF_PASS: skip; (.opencode/agents/ already exists)
    IF_FAIL: mkdir -p ${LOCAL_AGENTS_DIR};
    VERIFY:  test -d ${LOCAL_AGENTS_DIR};
  </STEP_2_AGENTS_DIR>

  <!-- ──────────────── STEP 3 — Create reviewer subagent ──────────────── -->

  <STEP_3_REVIEWER>
    GATE:   test -f ${LOCAL_AGENTS_DIR}${AGENT_REVIEWER}.md;
    IF_PASS: skip; (reviewer subagent already defined)
    IF_FAIL:
      FILE: ${LOCAL_AGENTS_DIR}${AGENT_REVIEWER}.md;
      CONTENTS: see reviewer.md template in this repo;
      KEY_PROPERTIES:
        mode: subagent
        description: Reviews code for correctness, security, and maintainability
        permission:
          edit: deny  — cannot modify files
          bash: deny  — cannot run commands
          read: allow — must inspect code
          grep: allow — must search code
          glob: allow — must find files
          task: deny  — cannot spawn subagents
      VERIFY: test -f ${LOCAL_AGENTS_DIR}${AGENT_REVIEWER}.md;
  </STEP_3_REVIEWER>

  <!-- ──────────────── STEP 4 — Create tester subagent ──────────────── -->

  <STEP_4_TESTER>
    GATE:   test -f ${LOCAL_AGENTS_DIR}${AGENT_TESTER}.md;
    IF_PASS: skip; (tester subagent already defined)
    IF_FAIL:
      FILE: ${LOCAL_AGENTS_DIR}${AGENT_TESTER}.md;
      CONTENTS: see tester.md template in this repo;
      KEY_PROPERTIES:
        mode: subagent
        description: Runs project test suites and reports results
        permission:
          edit: deny  — cannot modify files
          read: allow — must read test output
          bash:
            "*": deny
            "npm test*": allow
            "npm run test*": allow
            "pnpm test*": allow
            "pnpm run test*": allow
            "bun test*": allow
            "pytest*": allow
            "go test*": allow
            "cargo test*": allow
      VERIFY: test -f ${LOCAL_AGENTS_DIR}${AGENT_TESTER}.md;
  </STEP_4_TESTER>

  <!-- ──────────────── STEP 5 — Create orchestrator ──────────────── -->

  <STEP_5_ORCHESTRATOR>
    GATE:   test -f ${LOCAL_AGENTS_DIR}${AGENT_ORCHESTRATOR}.md;
    IF_PASS: skip; (orchestrator already defined)
    IF_FAIL:
      FILE: ${LOCAL_AGENTS_DIR}${AGENT_ORCHESTRATOR}.md;
      CONTENTS: see orchestrator.md template in this repo;
      KEY_PROPERTIES:
        mode: primary
        description: Decomposes tasks and dispatches parallel subagents
        permission:
          task:
            "*": deny
            "explore": allow
            "scout": allow
            "general": allow
            "reviewer": allow
            "tester": allow
          edit: allow
          bash: ask
      VERIFY: test -f ${LOCAL_AGENTS_DIR}${AGENT_ORCHESTRATOR}.md;
  </STEP_5_ORCHESTRATOR>

  <!-- ──────────────── STEP 6 — Create WORKFLOW_STATE.md ──────────────── -->

  <STEP_6_HANDOFF>
    GATE:   test -f ${PROJECT_ROOT}/${HANDOFF_FILE};
    IF_PASS: skip; (handoff file already exists)
    IF_FAIL:
      FILE: ${PROJECT_ROOT}/${HANDOFF_FILE};
      CONTENTS:
        # Workflow State
        <!--
          This file is the canonical record for multi-agent handoffs.
          Every agent reads it before starting work and updates its own
          section after completing.

          Sections:
            PLAN    — scope, acceptance criteria, implementation plan
            CHANGES — what was implemented / modified
            REVIEW  — review findings (PASS / items to address)
            TESTS   — test results (PASS / FAIL)
            STATUS  — current phase: planned | in-progress | review | done
        -->
      VERIFY: test -f ${PROJECT_ROOT}/${HANDOFF_FILE};
  </STEP_6_HANDOFF>

  <!-- ──────────────── STEP 7 — Wire task permissions ──────────────── -->

  <STEP_7_PERMISSIONS>
    GATE:   grep -q '"task"' ${PROJECT_ROOT}/opencode.json 2>/dev/null || (test -f ${LOCAL_AGENTS_DIR}${AGENT_ORCHESTRATOR}.md && grep -q "task:" ${LOCAL_AGENTS_DIR}${AGENT_ORCHESTRATOR}.md);
    IF_PASS: skip; (task permissions already configured)
    IF_FAIL:
      INSTRUCT:
        The orchestrator agent (step 5) includes a `permission.task` block
        that gates which subagents it can spawn. By default it allows only
        `explore`, `scout`, `general`, `reviewer`, and `tester` — denying all others.

        This prevents the model from arbitrarily delegating to any agent.
        Extend the allowlist in the orchestrator's config as needed.

        Pattern:
          permission:
            task:
              "*": deny
              "explore": allow
              "scout": allow
              "reviewer": allow
              "tester": allow
              "general": allow    ; opt-in as needed
      VERIFY: test -f ${LOCAL_AGENTS_DIR}${AGENT_ORCHESTRATOR}.md && grep -q '"task"\|task:' ${LOCAL_AGENTS_DIR}${AGENT_ORCHESTRATOR}.md;
  </STEP_7_PERMISSIONS>

  <!-- ──────────────── STEP 8 — Verify ──────────────── -->

  <STEP_8_VERIFY>
    GATE:   false;  (always run verification)
    IF_FAIL:
      INSTRUCT:
        1. Open a session in the project directory.
        2. Ask the orchestrator: "Analyze the project structure and
           list the custom agents available."
        3. Confirm the model lists: reviewer, tester, explore, scout.
        4. Ask: "Review the code in src/ for any issues"
           — confirm it invokes @reviewer.
        5. Check that WORKFLOW_STATE.md exists and contains the
           REVIEW section after the review completes.
      VERIFY: echo "Manual verification complete — agent pipeline operational.";
  </STEP_8_VERIFY>

</STEPS>

<AGENTS_REFERENCE>
  ; ── Built-in subagents (available without config) ──────────────
  ;
  ; @explore  — read-only research, file searches, codebase understanding.
  ;             Fast, cannot modify files. Use for upfront codebase mapping.
  ;
  ; @general  — full tool access (except todowrite). Use for implementation
  ;             work that doesn't fit a specialist agent.
  ;
  ; @scout    — read-only external docs and dependency research. Clones
  ;             dependency repos into managed cache. Cannot modify workspace.
  ;
  ; ── Custom subagents (created in steps above) ──────────────────
  ;
  ; @reviewer — read-only code review. Inspects diffs for correctness,
  ;             security, regressions, missing tests. Files findings in
  ;             WORKFLOW_STATE.md. Cannot edit code or run commands.
  ;
  ;   Model:  ${MODEL_REASONING}
  ;   Temperature: 0.1
  ;   Permission:   edit=deny, bash=deny, read=allow, grep=allow, glob=allow
  ;
  ; @tester   — test-only execution. Runs the project test suite and
  ;             records results in WORKFLOW_STATE.md. Cannot edit code.
  ;
  ;   Model:  ${MODEL_FAST}
  ;   Temperature: 0.1
  ;   Permission:   edit=deny, read=allow, bash=scoped to test commands only
  ;
  ; ── Custom primary agents ──────────────────────────────────────
  ;
  ; @orchestrator — primary agent that decomposes tasks and dispatches
  ;                 parallel subagents via the `task` tool. Scoped task
  ;                 permissions prevent arbitrary delegation.
  ;
  ;   Model:  ${MODEL_REASONING}
  ;   Temperature: 0.15
  ;   Permission:   task scoped to {explore, scout, general, reviewer, tester},
  ;                 edit=allow, bash=ask
</AGENTS_REFERENCE>

<GOTCHAS>
  ; SUBAGENTS DO NOT INHERIT CONTEXT. Each subagent starts with zero
  ; session history. You MUST include all necessary scope, constraints,
  ; file paths, and output format in each self-contained prompt.
  ;
  ; DISPATCH ALL AT ONCE. Sending one task tool call per response =
  ; sequential execution. Batch every independent task into the same
  ; response to achieve parallelism.
  ;
  ; PROVIDER CONCURRENCY LIMITS. Most providers cap parallel requests.
  ; Claude Max20: ~3 parallel tasks. Start with MAX_CONCURRENT_TASKS=2
  ; and increase only after clean runs. Beyond the ceiling causes
  ; timeouts and flaky completions, not faster results.
  ;
  ; TASK PERMISSIONS GATE THE MODEL, NOT THE USER. Users can always
  ; invoke any subagent via @mention regardless of `permission.task`.
  ; The task permission only prevents the MODEL from spawning agents
  ; not on the allowlist.
  ;
  ; WORKFLOW_STATE.MD IS THE SOURCE OF TRUTH. Do not rely on chat
  ; history for handoff — agents get fresh context. The handoff file
  ; makes coordination deterministic and debuggable.
  ;
  ; REVIEW GATES PREVENT BAD MERGES. Always run @reviewer after
  ; implementation before accepting changes. Two-stage review (spec
  ; compliance → code quality) catches issues the implementer missed.
  ;
  ; TEMPERATURE MATTERS PER ROLE. Use 0.0-0.15 for implementers and
  ; reviewers (consistency). Use 0.2-0.3 for debaters and planners
  ; (need to challenge assumptions). Never go above 0.3 for code work.
  ;
  ; SMALL TASKS DON'T NEED ORCHESTRATION. Single-file edits or quick
  ; questions are faster with one agent. Orchestration overhead pays
  ; off at 5+ files or multi-step cross-cutting changes.
</GOTCHAS>
