# Token Optimization for OpenCode — Setup Guide

<SUBTITLE>
  Machine-agnostic playbook for reducing token spend in OpenCode.
  Run `scripts/setup-token-stack.sh` on the target machine — it scans the
  machine and tells you which layers are suitable; this document explains
  the layers, the decision rules, and the honest caveats.
</SUBTITLE>

---

## The Layered Model

<LAYERS>
  Token spend happens at several independent stages. Each layer attacks one
  stage, so the layers stack rather than compete — with two exceptions noted
  under [Conflicts](#conflicts).

  | Layer | What it saves | Tool | Gating signal |
  |---|---|---|---|
  | 0 · Session mechanics | Context-window bloat, per-turn overhead | OpenCode built-ins: `compaction {auto, prune, reserved}`, `small_model`, `setCacheKey` (Anthropic only) | Always safe |
  | 1a · Context retrieval | Tokens spent reading the repo | Codebase Memory MCP (code graph) | Any machine; single static binary |
  | 1b · Command output | Bash tool output (git/test/log spam) | rtk | Any machine; needs brew or cargo |
  | 2 · Read enforcement | Repeated/large file reads re-entering context | Token Optimizer MCP | RAM >= 16 GB |
  | 3 · Output style | Output tokens (model prose) | caveman skill | Optional |
  | 3 · Docs freshness | Wasted turns from wrong APIs | Context7 MCP | Optional; network |
</LAYERS>

## Decision Rules (driven by the scan)

<RULES>

  ### RAM
  - `< 16 GB` — skip Tier 2 (Token Optimizer runs a Node daemon per session; on
    low-RAM machines it competes with the editor, the browser, and the indexer).
  - `>= 16 GB` — Tier 2 is suitable. Pair with Tier 1a; verify hook ordering
    between rtk and Token Optimizer once (see [Conflicts](#conflicts)).
  - Indexing (Tier 1a) is RAM-first but releases memory after the pass; large
    repositories should be indexed while idle.

  ### Disk free
  - `< 20 GB` — warn. Index caches, node_modules, and media can fill the disk
    quickly. Clean up before installing.
  - `>= 40 GB` — all layers including optional ones are comfortable.

  ### LLM provider (from `auth.json`)
  - `anthropic` → enable `provider.anthropic.options.setCacheKey: true`.
    Cache **writes cost 1.25×** plain input tokens; the premium is repaid only
    when a prefix is reused, so it helps long sessions and hurts short ones.
    Model switches or instructions edits invalidate the cache.
  - any other provider (OpenAI-compatible, Gemini, etc.) → do **not** set
    `setCacheKey`; it is provider-specific. Prefer `compaction` + cheap models.
  - Routing gateways (OpenRouter, OrcaRouter, LiteLLM) automate the "cheap
    model" choice but cut **cost per token, not token count** — they are not a
    token-saving layer and don't stack with the layers above. Their "% savings"
    figures (e.g. OrcaRouter's "up to 40% lower cost", "cache hit −90%") are
    unverified marketing — benchmark locally before trusting. Privacy: prompts
    and code transit the gateway unless self-hosted (OrcaRouter-Lite is MIT,
    BYOK).

  ### OS / arch
  - macOS arm64 (Apple Silicon) and amd64: prebuilt static binaries available
    for both CBM and rtk (Homebrew bottle). No Rosetta, no Docker.
  - Linux arm64/x86_64: same binaries; install rtk via brew/cargo/release.
  - The setup script itself is POSIX bash (macOS/Linux); Windows requires the
    manual steps below (CBM ships a native Windows binary; rtk works natively).

  ### Tools detected
  - `brew` → `brew install rtk` (fastest). `cargo` → git install fallback.
  - `curl` required for the Codebase Memory MCP installer.
  - `python3` required for the JSONC config merge in `--apply`.

  ### OpenCode detection
  - CLI on PATH, **or** the macOS Desktop app (`/Applications/OpenCode.app`),
    **or** `OPENCODE_CLIENT` set. The Desktop app reads the same global config,
    so MCP entries written to `~/.config/opencode/opencode.json(c)` apply to it.

  ### Projects (via `--projects <dir>`)
  - Index candidates: git repos with >= ~25 source files.
  - Skip: content/media folders, static-only sites, config repos.
  - Add vendored/third-party dirs to `.gitignore` so the graph stays small —
    the indexer honors `.gitignore` and skips `node_modules`, `.venv`, `dist`,
    `build`, `__pycache__`, `Pods`, and similar automatically.
</RULES>

## The Scan -> Apply Loop

<WORKFLOW>

  ```bash
  # 1. See what this machine supports (no changes):
  ./scripts/setup-token-stack.sh --projects ~/code

  # 2. Apply Tier 0-1 (idempotent; timestamped backup of config first):
  ./scripts/setup-token-stack.sh --apply

  # 3. Index the projects you actually work on:
  ./scripts/setup-token-stack.sh --index ~/code/app ~/code/lib

  # 4. Restart OpenCode. In each repo, tell the agent to "index this project".
  ```

  **Scope:** `--apply` installs **Tier 0 + Tier 1 only** (compaction config,
  Codebase Memory MCP, rtk + its OpenCode plugin). Tier 2 and Tier 3 are
  deliberately **manual**:
  - Tier 2 (Token Optimizer MCP, RAM >= 16 GB): add to `opencode.json` `mcp`
    block — `npx -y @ooples/token-optimizer-mcp@latest` — plus its integration
    `AGENTS.md` block from github.com/ooples/token-optimizer-mcp. Verify hook
    ordering with rtk once (see [Conflicts](#conflicts)).
  - Tier 3: `npx skills add JuliusBrussee/caveman`; Context7 MCP per its docs.
</WORKFLOW>

## Conflicts & Redundancies

<CONFLICTS>

  - **One graph engine only.** Codebase Memory MCP, Vexp, and code-review-graph
    all build code graphs. Running two doubles indexing work and injects two
    competing tool sets (and, in the case of Vexp/AGENTS.md guidance, competing
    instructions) into every turn. Pick one — Codebase Memory MCP is the free
    default.
  - **rtk vs Token Optimizer** both police shell reads (rtk rewrites commands,
    Token Optimizer denies `cat`/`grep -r` and redirects). Their pre-execution
    hook order is undocumented — test them together once. If they fight, drop
    Token Optimizer; rtk captures most of the bash win.
  - **prompt-caching MCP** duplicates the built-in `setCacheKey` for Anthropic —
    use the built-in, skip the plugin.
  - **Tool-schema overhead:** every MCP server adds its tool names + schemas to
    the context each turn. Beyond ~3-4 servers you start *spending* input
    tokens to look optimized. Lean stack, not wide stack.
</CONFLICTS>

## Honest Caveats

<CAVEATS>

  - Vendor "% savings" figures (Vexp, GemKit, prompt-caching) are marketing.
    Trust only measured claims: Codebase Memory MCP (arXiv preprint — ~10x
    fewer tokens, 2.1x fewer tool calls on structural queries), Token Optimizer
    (randomized control arm), rtk (dilution math documented in-repo), caveman
    (committed benchmarks; output tokens only).
  - `compaction.prune: true` deletes old tool outputs. In long debugging
    sessions the model may re-run commands to recover pruned context. Disable
    `prune` if orchestration/multi-agent sessions suffer.
  - rtk compresses *bash tool* output only; OpenCode built-in Read/Grep/Glob
    bypass it. It is a layer, not the whole answer.
  - `--apply` rewrites the OpenCode config as **plain JSON** when it needs to
    add settings — `//` comments and commented-out entries are removed from the
    *active* file (a timestamped `.bak.<ts>` is created first, so nothing is
    lost). Review the backup before discarding it.
  - Indexes go stale if the watcher misses changes; re-index on demand, or
    commit the `.codebase-memory/graph.db.zst` artifact so clones bootstrap
    incrementally.

## Maintenance

<MAINTENANCE>

  - Re-run the scanner on any new machine: `scripts/setup-token-stack.sh`.
  - Update tools: `codebase-memory-mcp update` (runs its install script),
    `brew upgrade rtk`.
  - Uninstall CBM: `codebase-memory-mcp uninstall`. rtk:
    `rtk init -g --uninstall` + `brew uninstall rtk`.
</MAINTENANCE>

---

<LICENSE>
  Configuration + tooling template for OpenCode. Use freely.
</LICENSE>
