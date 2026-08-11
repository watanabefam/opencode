# opencode — AI-Configurable Dev Tooling

This repo is the **opencode CLI** itself. When working here, your primary job is to help configure and improve the user's opencode setup so that AI agents can reliably configure, customize, and maintain opencode on any machine they run on. All code changes, agent definitions, config files, and documentation should serve this goal.

## Gap Analysis

<GAP_ANALYSIS>
Run this block first to discover which setup steps are needed on the current machine.

<CHECKS>
  Global config (opencode.jsonc):         test -f ~/.config/opencode/opencode.jsonc;
  Global agents dir:                      test -d ~/.config/opencode/agents;
  Orchestrator agent (local):             test -f .opencode/agents/orchestrator.md;
  Orchestrator agent (global fallback):   test -f ~/.config/opencode/agents/orchestrator.md;
  Reviewer agent (local):                 test -f .opencode/agents/reviewer.md;
  Tester agent (local):                   test -f .opencode/agents/tester.md;
  AGENTS.md has subagent reference:       test -f AGENTS.md && grep -q "Subagent Reference" AGENTS.md;
  WORKFLOW_STATE.md has TASKS:            test -f WORKFLOW_STATE.md && grep -q "TASKS" WORKFLOW_STATE.md;
  WORKFLOW_STATE.md has HANDOFFS:         test -f WORKFLOW_STATE.md && grep -q "HANDOFFS" WORKFLOW_STATE.md;
  WORKFLOW_STATE.md has RUN_LOG:          test -f WORKFLOW_STATE.md && grep -q "RUN_LOG" WORKFLOW_STATE.md;
  Repo opencode.json has default_agent:   test -f opencode.json && grep -q "default_agent" opencode.json;
  Repo instructions files exist:          for f in hybrid-format-convention.md workspace-convention.md docs/browser-automation-efficiency.md; do test -f "$f" || exit 1; done;
</CHECKS>
</GAP_ANALYSIS>

## Architecture

<ARCHITECTURE>
Data flow for an opencode session:

```
User input
    │
    ▼
opencode.json(c) ──► ConfigLoader ──► merged config (project + global)
    │                                      │
    │                          ┌───────────┴───────────┐
    │                          │                       │
    │                     default_agent          instructions
    │                          │                    [.md files]
    │                          ▼                       │
    │                   ConfigAgent.load()             │
    │                   (scans ConfigPaths             │
    │                    directories for               │
    │                    agents/ subdirs)               │
    │                          │                       │
    └──────────┬───────────────┴───────────┬───────────┘
               │                           │
               ▼                           ▼
         Agent prompt             Instruction files
         (orchestrator.md)        (AGENTS.md + *.md)
               │                           │
               └───────────┬───────────────┘
                           │
                           ▼
                Session system prompt
                           │
                           ▼
                    LLM (model)
                           │
                    ┌──────┴──────┐
                    │             │
                    ▼             ▼
              Tool calls      Response text
                    │
         ┌──────────┼──────────┐
         │          │          │
         ▼          ▼          ▼
      task()    MCP servers   filesystem/bash
   (subagents)   (mcp block)   (permissions)
         │
         ▼
   WORKFLOW_STATE.md
   (TASKS + RUN_LOG + HANDOFFS)
```

Key subsystems:
- **ConfigLoader** — merges project `opencode.json` with global `opencode.jsonc`. Arrays are concatenated, scalars prefer project.
- **ConfigPaths.directories()** — agent discovery order: project `.opencode/` → `~/.opencode/` → `~/.local/share/opencode/` → `~/.config/opencode/`
- **Instructions** — `.md` files loaded into system prompt. Relative paths resolve upward from project root. `~/` paths resolve to home directory. HTTP URLs fetched remotely.
- **Agent prompt** — `.md` body after YAML frontmatter. Only loaded when that agent is the active primary agent.
- **WORKFLOW_STATE.md** — canonical handoff file. Every agent reads before work and writes after. Sections: PLAN, TASKS, RUN_LOG, HANDOFFS, REVIEW, TESTS, STATUS.
</ARCHITECTURE>

## Subagent Reference

<SUBAGENT_REFERENCE>
| Agent | When to use | Can edit? |
|---|---|---|
| `@explore` | Read-only research, file searches, codebase understanding | No |
| `@general` | Full tool access, code changes, multi-step work | Yes |
| `@scout` | External docs and dependency research | No |
| `@reviewer` | Code review for correctness, security, regressions | No |
| `@tester` | Run project test suites and report results | No |
| `@orchestrator` | Decompose tasks and dispatch parallel workstreams | Yes |

Full orchestration system docs (task state machine, handoff protocol, cost tracking, retry policy, fan-in, human escalation gate, graceful degradation): `docs/orchestration-reference.md`
</SUBAGENT_REFERENCE>

## Browser Automation & AI Browser Tooling

When a task involves browser automation (E2E tests, scraping, AI-driven browsing, or driving the user's real logged-in browser), follow the verified recommendations below — and the safe-adoption rules so opencode itself is never broken. Read `docs/browser-automation-efficiency.md` (deep playbook, tool-specific configs, verification table, adoption checklist) before implementing anything.

## Recommendations (verified, ranked by impact)
<RECOMMENDATIONS>

1. **Baseline Playwright efficiency first** (free, zero new deps) — parallelism/sharding (`fullyParallel`, `--shard`, merge `blob` reports), block heavy resources via `page.route` (abort images/fonts/media; `route.fulfill` slow APIs), reuse auth via `storageState` + setup project, trace/video only on retry (`'on-first-retry'`), semantic locators (`getByRole`/`getByTestId`), never `waitForTimeout` — rely on auto-wait + tuned `expect.timeout`.
2. **AI-agent token efficiency → `@playwright/cli`** (official Microsoft, experimental pre-1.0 — keep current; track versions, don't freeze). Disk-based a11y-tree snapshots + warm daemon keep context small; `playwright-cli install --skills` writes to `.claude/skills/` which opencode auto-discovers. Reserve Playwright MCP for persistent/agentic loops.
3. **Drive the user's real logged-in browser** (SSO/2FA, LMS, Google Workspace) via the official **Playwright Extension**: `@playwright/mcp --extension` or `playwright-cli attach --extension`, gated by `PLAYWRIGHT_MCP_EXTENSION_TOKEN`. CRX (stale since 2025-06) and Playwriter (broadest permissions, ToS-risky features) are alternatives with caveats.
4. **Adopt the verified token-efficiency mechanisms** in any agent tooling: a11y-tree/ASCII-wireframe page views with indexed elements, constrained action schemas, action caching, hard step limits.
5. **Never cite unverified claims** — "26K vs 114K tokens", "Tappi", per-page token figures, "$0.07/10-step" are not primary-source-verified; benchmark locally before quoting.

**Default tool selection: CLI first.** Use `@playwright/cli` for agent-driven browser automation (measured token efficiency, disk-based state, zero config-crash risk). Fall back to Playwright MCP only for persistent agentic loops, vision/screenshot-driven steps, or CLI errors/unsupported features; use headed/UI Mode only for interactive debugging. If the CLI misbehaves, try `playwright-cli --help` / self-discovery before switching; keep tools current and track versions (track, don't freeze — see doc §2.6). Policy detail + rationale: `docs/browser-automation-efficiency.md` §Default tool-selection policy; local benchmark: WORKFLOW_STATE.md TASK-017.

</RECOMMENDATIONS>

## Safe-adoption rules (never break opencode)
<SAFE_ADOPTION>

1. **Validate JSONC before saving any opencode config**: strip `//` comments (never inside `https://`), remove trailing commas, then `JSON.parse`. A malformed `opencode.json` crashes opencode at load (#35954); a bad MCP entry also crashes it at load (#33845). Prefer `edit` over full rewrites.
2. **MCP entries**: `"type": "local"` + `command` as an **array** (`["npx", "-y", "@playwright/mcp@latest", "--isolated"]` — `-y` prevents the non-TTY npx hang; keep current, see doc §2.6). Env vars (`PLAYWRIGHT_MCP_EXTENSION_TOKEN`, `{env:VAR}`) go in `environment`, **never** inside a `command` element. Remote MCP: `"type": "remote"` + `url` + `"timeout": 30000`.
3. **Name MCP servers uniquely** (e.g. `pw-browser`, not `playwright`) to avoid tool-prefix collisions with other `playwright_*` servers; disable leftovers with `"tools": { "<name>_*": false }`.
4. **Skills**: install via `npx -y skills add <repo> -a opencode -y` (targets `.agents/skills/` + `~/.config/opencode/skills/`), or accept `.claude/skills/` output — all opencode-discovered. `SKILL.md` frontmatter needs `name`+`description`; name must match the folder (lowercase-kebab).
5. **Permissions**: extension-driven browser actions bypass opencode's `permission` model (the MCP process does the work). Don't loosen opencode's own permission config for this; gate real-browser access via the extension's approval/token flow instead.
6. **Keep experimental tools current, track their versions** — after any upgrade (or when behavior changes), record the running version (`playwright-cli --version` / resolved npx version) in WORKFLOW_STATE.md and run the smoke test; never freeze versions in the always-on config. Use `--isolated` to avoid persistent-profile lock conflicts. `@playwright/cli` bundles Playwright alpha builds — expect occasional breakage and use the fallback ladder.
7. **Security**: extensions with `debugger` + `<all_urls>` can read/act on logged-in pages — attach only intended tabs; review third-party extension source before installing (Playwriter requests `identity`/`identity.email`); avoid ToS-violating "bypass bot detection" features.

</SAFE_ADOPTION>

Full playbook (configs, verification table, adoption checklist): `docs/browser-automation-efficiency.md`.
