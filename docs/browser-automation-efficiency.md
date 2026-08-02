# Browser Automation Efficiency — Verified Playbook & Safe Adoption

<DOC_HEADER>
  Canonical reference for making Playwright / browser automation more efficient AND adopting those tools
  without breaking opencode. Applies to any machine that runs opencode: agents on a new machine read this
  and implement the same rules. The always-loaded summary lives in AGENTS.md
  ("Browser Automation & AI Browser Tooling"); this file is the deep detail.
</DOC_HEADER>

## How to use this document
<HOW_TO_USE>

- **Browser automation task?** Read Part 1 (recommendations) + Part 2 (safety rules) first.
- **Adding an MCP server / skill / extension to opencode config?** Part 2 is mandatory reading.
- **Building or tuning an AI browsing agent?** Part 4 (token-efficiency mechanisms).
- **Quoting numbers in docs or prompts?** Check Part 5 (verification table) — several viral claims are NOT primary-source-verified.
- **Onboarding a new machine?** Run the Part 6 checklist.

</HOW_TO_USE>

## Part 1 — Verified recommendations (ranked by impact)
<PART1>

1. **Baseline Playwright efficiency first (free, zero new dependencies).** This is the highest-value, lowest-risk set — all documented on playwright.dev:
   - Parallelism: `fullyParallel: true` + `--shard=1/N` across CI, merge `blob` reports (`npx playwright merge-reports`); workers default to 50% of cores (RAM is the real ceiling); `workers: 1` + sharding is the stable CI pattern.
   - Resource blocking: `page.route` to abort images/fonts/media/third-party and `route.fulfill` slow APIs — the biggest per-test runtime cut.
   - Auth reuse: `storageState` + setup project (or per-worker fixture) to skip login UI every test/worker.
   - Artifacts on retry only: `trace/video: 'on-first-retry'` (suite-wide `trace: 'on'` is "very performance heavy" per docs).
   - Semantic locators (`getByRole`/`getByTestId`) over CSS/XPath; never `waitForTimeout` — auto-wait + tuned `expect.timeout`/`actionTimeout`.
2. **AI-agent token efficiency → `@playwright/cli`** (npm `@playwright/cli`, official Microsoft, Apache-2.0, experimental pre-1.0 — **pin versions**; bundles Playwright alpha builds). Efficiency design is real and verified: disk-based a11y-tree snapshots (`.playwright-cli/page-*.yml`, ref-based interaction, `--output-max-size` evicts to disk), warm daemon (no per-command startup), accessibility-tree output instead of screenshots, `playwright-cli install --skills`. Reserve Playwright MCP for persistent/agentic loops.
3. **Driving the user's real logged-in browser** (SSO/2FA, LMS, Google Workspace) — use the official **Playwright Extension** (Microsoft-published, MV3): `@playwright/mcp --extension` or `playwright-cli attach --extension`, gated by `PLAYWRIGHT_MCP_EXTENSION_TOKEN`. Reuses real cookies/profiles — no re-authentication.
4. **Token-efficiency mechanisms for agent tooling** (verified across Stagehand/browser-use/Skyvern/Agent Browser): a11y-tree/ASCII-wireframe page views with indexed interactive elements, constrained action schemas, action caching/self-healing, hard step limits. See Part 4.
5. **Escalation options when baseline isn't enough:**
   - Cloud browser platforms (keep your Playwright code): Browserbase (`chromium.connectOverCDP`), Steel (open-source, self-hostable), Browserless.
   - AI agents: browser-use (OSS; Cloud metered ~$0.006/step), Stagehand (Playwright + LLM hybrid, TypeScript), Skyvern (Playwright extension, vision-based, AGPL-3.0).
   - Anti-detection: Camoufox (engine-level, strongest free; ~1yr maintenance gap — verify), rebrowser-patches (CDP leak fix), playwright-extra/stealth (easy, weaker).
   - Volume scraping: Zenrows / ScrapingBee / ScraperAPI / Bright Data Web Unlocker (cheapest per-1k for simple pages; Web Unlocker must NOT be driven by Playwright — use their Scraping Browser instead).

</PART1>

## Part 2 — Safe implementation in opencode (never break the config)
<PART2>

### 2.1 Config crash rules (verified against opencode docs + upstream issues)
<CONFIG_CRASH_RULES>

- **A malformed `opencode.json` crashes opencode at load** with no recovery (upstream #35954 — an agent's string-edit corrupted the file → JSON parse error → crash).
- **A bad MCP entry crashes opencode at load** (upstream #33845 — `"type": "streamable_http"` crashed on startup instead of being rejected).
- **Therefore: validate JSONC before saving.** Strip `//` comments (but NOT the `//` in `https://`), remove trailing commas, then `JSON.parse`. Prefer surgical `edit` operations over full-file rewrites.
- A missing `instructions` file **warns but does not crash** — still, keep every listed file on disk.

</CONFIG_CRASH_RULES>

### 2.2 MCP server config (verified shape)
<MCP_CONFIG>

`@playwright/mcp` is an officially documented opencode client (microsoft/playwright-mcp README, added via PR #895):

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "pw-browser": {                      // unique name — avoids `playwright_*` tool-prefix collisions
      "type": "local",
      "command": ["npx", "-y", "@playwright/mcp@<pinned-version>", "--isolated"],  // pin a real released version (npm view @playwright/mcp versions); -y = no non-TTY prompt; --isolated = no profile lock
      "enabled": false                   // opt-in: keep false unless the user wants it on every session
    }
  }
}
```

Rules that apply to ANY MCP entry:
- `"type": "local"` + `command` as an **array** (never a string). `npx` must include `-y` or a non-TTY spawn hangs on the "Ok to proceed?" prompt.
- Env vars — including `{env:VAR}` and `PLAYWRIGHT_MCP_EXTENSION_TOKEN` — go in the `environment` block (string values only), **never inside a `command` array element** (command args are literal).
- Remote MCP: `"type": "remote"` + `url` + `"timeout": 30000`.
- Tool name prefix = `{server}_{tool}`. If a leftover server is unwanted, disable via `"tools": { "<name>_*": false }` (glob supported). Never disable opencode built-ins.
- MCP servers add to model context on every session — keep the enabled set small; `"enabled": false` until explicitly wanted.

</MCP_CONFIG>

### 2.3 Skills (verified discovery paths)
<SKILLS_CONFIG>

- opencode discovers skills in: `.opencode/skills/`, `~/.config/opencode/skills/`, plus Claude-compatible `.claude/skills/` / `~/.claude/skills/` and `.agents/skills/` / `~/.agents/skills/`.
- `playwright-cli install --skills` writes to `.claude/skills/playwright-cli/SKILL.md` — works in opencode with zero copying (unknown frontmatter fields like `allowed-tools` are ignored by current opencode versions — re-verify after upgrades).
- The `skills` CLI (`vercel-labs/skills`, npm `skills`) has a first-class opencode target: `npx -y skills add <owner/repo> -a opencode -y` → installs to `.agents/skills/` (project) and `~/.config/opencode/skills/` (global). Use `--copy` instead of the default symlink if you want standalone files.
- `SKILL.md` frontmatter: `name` (lowercase-kebab, must match the folder name, 1–64 chars) + `description` (≤1024 chars) required.

</SKILLS_CONFIG>

### 2.4 Permissions model (verified)
<PERMISSIONS_MODEL>

- opencode's `permission` config governs opencode's own tools (bash/files). **MCP-internal actions are not governed by it** — an extension-driven automation runs in the MCP process, bypassing opencode's bash permission prompts.
- Do NOT loosen opencode's permission config to accommodate browser automation. Gate real-browser access via the extension's own per-connection approval flow or `PLAYWRIGHT_MCP_EXTENSION_TOKEN`.

</PERMISSIONS_MODEL>

### 2.5 Extension & security rules (verified)
<EXTENSION_SECURITY>

- Any extension with `debugger` + `<all_urls>` (official Playwright Extension, Playwriter) can read and act on every page you log into. Attach only intended tabs; keep the approval/token flow intact.
- Trust signals (verified): official Playwright Extension = Microsoft first-party, leanest perms (`debugger, activeTab, tabs, tabGroups` + all_urls), ~70k users. Playwright CRX = third-party (rui.figueira), stale (last CWS update 2025-06), record/play only. Playwriter = third-party (MIT, 3.7k★, active), broadest perms (`debugger, scripting, tabs, tabCapture, identity, identity.email, webNavigation` + all_urls) — review its open-source extension before installing; it advertises bot-detection bypass (ToS risk).
- Never automate CAPTCHA solving or "stealth" evasion as a default — ToS risk and unreliable.

</EXTENSION_SECURITY>

</PART2>

## Part 3 — Tool playbooks
<PART3>

### 3.1 `@playwright/cli` (official, for coding agents)
<PLAYBOOK_CLI>

```bash
npm install -g @playwright/cli@latest        # or pin @playwright/cli@0.1.x
playwright-cli install --skills              # writes .claude/skills/playwright-cli/ (opencode-discovered)
playwright-cli open https://example.com --headed   # headless by default; --headed opt-in
playwright-cli install-browser [--with-deps] # documented flow (auto-downloads on first use otherwise)
```

- Agent loop: run shell commands; each returns a file link to the a11y snapshot; act via element refs (`click e15`) or locators; `--json`/`--raw` for scriptable output; `find` greps large snapshots; `-s <name>` isolates sessions; `state-save/load` + `--persistent` handle auth.
- Attach to the user's real browser: `playwright-cli attach --extension[=chrome]` (requires the Playwright Extension) or `attach --cdp=chrome`.
- Not verified (do not quote): "26K vs 114K tokens", Antigravity integration, POM generation via CLI.

</PLAYBOOK_CLI>

### 3.2 `@playwright/mcp` (official, persistent/agentic loops)
<PLAYBOOK_MCP>

- Config: see Part 2.2. Flags as `command` args or `PLAYWRIGHT_MCP_*` env: `--isolated`, `--headless`/`--headed`, `--browser chrome|firefox|webkit|msedge`, `--extension`, `--user-data-dir`, `--storage-state`, `--device`, `--mobile`.
- `--extension` requires the Playwright Extension (CWS `mmlmfjhmonkocbjadbfplnigmagldckm`); per-connection approval or `PLAYWRIGHT_MCP_EXTENSION_TOKEN` (set in MCP `environment`).
- Concurrent sessions sharing a workspace conflict on the persistent profile — use `--isolated` or distinct `--user-data-dir`.

</PLAYBOOK_MCP>

### 3.3 Agent Browser (`@agent-browser-io/browser`)
<PLAYBOOK_AGENT_BROWSER>

- MIT, TypeScript, experimental (v0.3.x, ~42★). ASCII-wireframe output with indexed elements `[1]…[137]`; stdio MCP server (`npx @agent-browser-io/browser mcp`); Vercel AI SDK tools with `stepCountIs(20)` step limits. Playwright backend.
- Per-page token figures are unverified — benchmark locally. No Python binding.

</PLAYBOOK_AGENT_BROWSER>

### 3.4 Cloud / anti-detect / scraping (escalation only)
<PLAYBOOK_ESCALATION>

- **Cloud browsers** (keep your Playwright code): Browserbase `chromium.connectOverCDP(session.connectUrl)`; Steel open-source/self-host; Browserless units-based. Use when infra offload or persistent cloud sessions matter; watch latency/cost (browser-hour pricing vs ~$1–4/1k for scraping APIs).
- **Anti-detect**: Camoufox (engine-level, drop-in Playwright API, free — but maintenance gap), rebrowser-patches (free, CDP leak fix), playwright-extra stealth (easy, weaker).
- **Scraping APIs**: Zenrows, ScrapingBee, ScraperAPI, Bright Data Web Unlocker — REST, no browser to maintain, cheapest per-1k for simple pages. Bright Data Web Unlocker must NOT be used with Playwright.

</PLAYBOOK_ESCALATION>

</PART3>

## Part 4 — Token-efficiency mechanisms for AI-agent design
<PART4>

Verified mechanisms used by Stagehand / browser-use / Skyvern / Agent Browser:

1. **Return a compressed page representation, never raw HTML** — accessibility tree or ASCII wireframe with numbered interactive elements (this is the core of every token-efficient tool).
2. **Act by element index, not selector interpretation** — removes an LLM "interpretation layer" and its tokens.
3. **Constrain the action schema** to a small set (`navigate / click / type / extract / scroll`) — fewer hallucinated actions.
4. **Cache repeatable actions / self-heal** — repeat runs skip LLM inference entirely (Stagehand: "cache repeatable actions to save time and tokens").
5. **Hard step limits** — prevents runaway loops (`stepCountIs(20)`, max-steps).
6. **Hierarchical + differential snapshots** — interactive-roles-only views, then deltas between steps (technique defensible; published percentages are NOT benchmarked).
7. **Sanitize page content / allowlist domains** — prompt-injection guard.

</PART4>

## Part 5 — Claims verification table (what you may and may not cite)
<PART5>

| Claim | Verdict | Source |
|---|---|---|
| `@playwright/cli` is official Microsoft (Apache-2.0 per npm metadata), for AI coding agents | ✅ Verified | npm (Microsoft), playwright.dev/agent-cli, microsoft/playwright-cli |
| CLI is more token-efficient than MCP (disk-based a11y snapshots, daemon) | ✅ Verified (qualitative) | npm README, docs; MCP docs cite ~200–400 tokens/snapshot |
| **"~26K tokens/task vs ~114K for Playwright MCP"** | ❌ **UNVERIFIED** — in no primary source (YouTube/marketing origin) | — |
| **Tappi "~200 tokens/page, 10x fewer than Playwright CLI"** | ❌ **UNVERIFIABLE** — dev.to article deleted; no npm/GitHub "Tappi" exists; maps to author's 0-star `browser-js` | — |
| **Agent Browser "~1,000–3,000 tokens/page"** | ❌ UNVERIFIED — not stated in any primary source | — |
| **Browser Use "~$0.07/10-step task"** | ⚠️ Partial — OSS free (pay own LLM); matches Cloud API V2 only ($0.006/step + $0.01/task) | browser-use.com/pricing |
| Stagehand action caching cuts tokens | ✅ Verified | stagehand README |
| Skyvern vision-based, no selectors | ✅ Verified (AGPL-3.0) | skyvern README |
| a11y tree = 90%+ token reduction | ⚠️ Mechanism sound; percentages unbenchmarked | gist 0xK8oX/638e… |
| Official Playwright Extension = Microsoft, MV3, session reuse | ✅ Verified | Chrome Web Store, microsoft/playwright `packages/extension` |
| `@playwright/mcp` documented for opencode | ✅ Verified | microsoft/playwright-mcp README (PR #895) |
| Bad MCP entry / malformed JSON crashes opencode | ✅ Verified | opencode issues #33845, #35954 |

**Rule: benchmark token usage on your own pages before quoting any per-page/per-task figure.**

</PART5>

## Part 6 — Machine adoption checklist
<PART6>

- [ ] `AGENTS.md` present (grep "Browser Automation & AI Browser Tooling") and this doc exists (`docs/browser-automation-efficiency.md`) — Gap Analysis verifies both.
- [ ] Decide with the user whether Playwright MCP is wanted session-wide; if yes, add per Part 2.2 with `"enabled": false` first, then enable after validating `opencode.json` JSONC parses.
- [ ] Validate any config edit: strip comments (not `https://`), drop trailing commas, `JSON.parse`.
- [ ] Pin versions of experimental tools (`@playwright/cli`, `@playwright/mcp`); use `--isolated`.
- [ ] Install skills via `npx -y skills add <repo> -a opencode -y` or accept `.claude/skills/` output; verify `SKILL.md` frontmatter.
- [ ] For real-browser automation: official Playwright Extension only; set `PLAYWRIGHT_MCP_EXTENSION_TOKEN` in `environment`; never loosen opencode `permission`.
- [ ] Security review before installing third-party automation extensions (Playwriter: review source; broadest permissions).
- [ ] Baseline benchmark: run the same task with raw Playwright vs CLI vs MCP, count tokens (via `--json`/`--raw` output), record in WORKFLOW_STATE.md RUN_LOG.

</PART6>

## Sources
<SOURCES>

- https://playwright.dev/docs (test-parallel, test-sharding, network, auth, best-practices, debug, browsers, chrome-extensions, agent-cli, mcp)
- https://www.npmjs.com/package/@playwright/cli · https://github.com/microsoft/playwright-cli
- https://github.com/microsoft/playwright-mcp (opencode config, PR #895)
- https://github.com/microsoft/playwright (packages/extension; chromiumSwitches.ts; issues #33566)
- https://github.com/browserbase/stagehand · https://github.com/browser-use/browser-use · https://github.com/Skyvern-AI/skyvern
- https://github.com/agent-browser-io/browser · https://github.com/daijro/camoufox · https://github.com/rebrowser/rebrowser-patches · https://github.com/apify/crawlee-python
- https://github.com/remorses/playwriter · https://github.com/ruifigueira/playwright-crx
- https://chromewebstore.google.com/detail/playwright-extension/mmlmfjhmonkocbjadbfplnigmagldckm
- https://chromewebstore.google.com/detail/playwright-crx/jambeljnbnfbkcpnoiaedcabbgmnnlcd
- opencode config/MCP/skills docs: https://opencode.ai/docs/config · /docs/mcp-servers · /docs/skills; upstream issues #33845, #35954
- gist (mechanisms, unbenchmarked): https://gist.github.com/0xK8oX/638e2069ccb933c199a0f02006278da7

</SOURCES>
