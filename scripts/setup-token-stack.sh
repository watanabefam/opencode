#!/usr/bin/env bash
# =============================================================================
# setup-token-stack.sh — scan any machine, then install & wire the
# token-optimization stack for OpenCode.
#
# This script is deliberately machine-agnostic. It NEVER hardcodes a username,
# a chip, a RAM figure, or a project path — it scans the machine it runs on
# and applies only what that machine can support (see docs/token-optimization.md
# for the decision rules).
#
# Layers it can install (each gated by the scan):
#   Tier 0  — OpenCode built-ins: compaction (auto/prune/reserved) — always safe
#   Tier 1  — Codebase Memory MCP (code-graph) + rtk (bash output compression)
#   Tier 2  — Token Optimizer MCP (read enforcement) — MANUAL, RAM >= 16 GB only
#   Tier 3  — caveman skill + Context7 MCP — MANUAL, optional
#
# NOTE: --apply installs Tier 0 + Tier 1 only. Tier 2/3 are manual (see
# docs/token-optimization.md for the steps). --index is exclusive: it runs
# indexing and exits; combine flags are ignored in favor of --index.
#
# Usage:
#   ./setup-token-stack.sh                      # scan + report only (default)
#   ./setup-token-stack.sh --apply              # scan + apply Tier 0-1
#   ./setup-token-stack.sh --projects <dir>     # include per-project scan
#   ./setup-token-stack.sh --index <dir> [...]  # (re)index project(s) with CBM
#   ./setup-token-stack.sh --quiet              # minimal output
#
# Exit codes: 0 = ok, 1 = error. (No other codes.)
# =============================================================================
set -euo pipefail

APPLY=0
QUIET=0
PROJECTS_DIR=""
INDEX_DIRS=()
LOG_PREFIX="[token-stack]"

log()  { if (( QUIET == 0 )); then printf '%s %s\n' "$LOG_PREFIX" "$*"; fi; }
warn() { printf '%s WARN: %s\n' "$LOG_PREFIX" "$*" >&2; }
die()  { printf '%s ERROR: %s\n' "$LOG_PREFIX" "$*" >&2; exit 1; }
add_agent() { [[ " $AGENTS " == *" $1 "* ]] || AGENTS="$AGENTS $1"; }

# --------------------------------------------------------------------------
# Argument parsing
# --------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)       APPLY=1 ;;
    --quiet)       QUIET=1 ;;
    --projects)    [[ $# -ge 2 ]] || die "--projects needs a directory"; PROJECTS_DIR="$2"; shift ;;
    --index)       shift; [[ $# -ge 1 ]] || die "--index needs at least one directory"
                   while [[ $# -gt 0 && "$1" != --* ]]; do INDEX_DIRS+=("$1"); shift; done
                   continue ;;
    -h|--help)     sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)             die "unknown argument: $1" ;;
  esac
  shift
done

# --------------------------------------------------------------------------
# Machine scan
# --------------------------------------------------------------------------
detect_os_arch() {
  OS="$(uname -s 2>/dev/null | tr '[:upper:]' '[:lower:]')"
  ARCH="$(uname -m 2>/dev/null)"
  case "$OS" in darwin|linux) : ;; *) warn "untested OS: $OS (macOS/Linux assumed)";; esac
  case "$ARCH" in x86_64|amd64) ARCH_NORM="amd64" ;; arm64|aarch64) ARCH_NORM="arm64" ;; *) ARCH_NORM="$ARCH" ;; esac
}

detect_ram_gb() {
  if [[ "$OS" == "darwin" ]]; then
    RAM_GB="$(sysctl -n hw.memsize 2>/dev/null | awk '{printf "%d", $1/1073741824}')"
  else
    RAM_GB="$(awk '/MemTotal/ {printf "%d", $2/1048576}' /proc/meminfo 2>/dev/null)"
  fi
  RAM_GB="${RAM_GB:-0}"
}

detect_disk_free_gb() {
  DISK_GB="$(df -k "$HOME" 2>/dev/null | awk 'NR==2 {printf "%d", $4/1048576}')"
  DISK_GB="${DISK_GB:-0}"
}

detect_tools() {
  TOOLS=""
  for t in brew node npx npm cargo curl git python3 uv docker jq; do
    command -v "$t" >/dev/null 2>&1 && TOOLS="$TOOLS $t"
  done
}

detect_agents() {
  AGENTS=""
  command -v opencode >/dev/null 2>&1 && add_agent opencode
  # macOS Desktop app is a valid OpenCode install even without a CLI on PATH
  if [[ "$OS" == "darwin" && -d "/Applications/OpenCode.app" ]]; then add_agent opencode; fi
  [[ -n "${OPENCODE_CLIENT:-}" ]] && add_agent opencode
  command -v claude  >/dev/null 2>&1 && add_agent claude
  command -v codex   >/dev/null 2>&1 && add_agent codex
  command -v gemini  >/dev/null 2>&1 && add_agent gemini
  [[ "$OS" == "darwin" && -d "/Applications/Cursor.app" ]] && add_agent cursor
  command -v cursor  >/dev/null 2>&1 && add_agent cursor
  [[ "$OS" == "darwin" && -d "/Applications/Windsurf.app" ]] && add_agent windsurf
  command -v aider   >/dev/null 2>&1 && add_agent aider
  return 0  # keep exit status 0 even when the last tool is absent (set -e safe)
}

# Locate the effective global OpenCode config file.
detect_opencode_config() {
  if [[ -n "${OPENCODE_CONFIG:-}" && -f "${OPENCODE_CONFIG:-}" ]]; then
    CONFIG_FILE="$OPENCODE_CONFIG"
  elif [[ -f "$HOME/.config/opencode/opencode.jsonc" ]]; then
    CONFIG_FILE="$HOME/.config/opencode/opencode.jsonc"
  elif [[ -f "$HOME/.config/opencode/opencode.json" ]]; then
    CONFIG_FILE="$HOME/.config/opencode/opencode.json"
  else
    CONFIG_FILE="$HOME/.config/opencode/opencode.jsonc"
  fi
  CONFIG_DIR="$(dirname "$CONFIG_FILE")"
  PLUGIN_DIR="$HOME/.config/opencode/plugins"
}

# Which LLM provider is authenticated? (drives caching advice)
detect_provider() {
  PROVIDERS=""
  for auth in "$HOME/.local/share/opencode/auth.json" "$HOME/.local/share/opencode/auth.jsonc"; do
    [[ -f "$auth" ]] || continue
    if command -v python3 >/dev/null 2>&1; then
      PROVIDERS="$(AUTH_FILE="$auth" python3 -c \
        "import json,os; print(' '.join(json.load(open(os.environ['AUTH_FILE'])).keys()))" 2>/dev/null || true)"
    fi
    break
  done
}

has_tool()  { [[ " $TOOLS " == *" $1 "* ]]; }
has_agent() { [[ " $AGENTS " == *" $1 "* ]]; }

# --------------------------------------------------------------------------
# Per-project scan (only when --projects <dir> is passed)
# --------------------------------------------------------------------------
scan_projects() {
  local root="$1"
  [[ -d "$root" ]] || die "--projects path is not a directory: $root"
  log "Scanning projects under: $root"
  printf '%s %-28s %-5s %-8s %-10s %s\n' "$LOG_PREFIX" "PROJECT" "GIT" "CODE" "NODE_MODS" "VERDICT"
  for d in "$root"/*/; do
    [[ -d "$d" ]] || continue
    local name; name="$(basename "$d")"
    [[ "$name" == .* ]] && continue
    local git="no" code=0 nm_size=""
    [[ -d "$d/.git" ]] && git="yes"
    code="$(find "$d" -type f \
      -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/dist/*" \
      -not -path "*/build/*" -not -path "*/vendor/*" -not -path "*/Pods/*" \
      -not -path "*/__pycache__/*" -not -path "*/.next/*" -not -path "*/.venv/*" \
      2>/dev/null | wc -l | tr -d ' ')"
    nm_size="$(du -sh "$d/node_modules" 2>/dev/null | cut -f1)"
    local verdict="skip"
    if (( code >= 25 )); then verdict="INDEX"; elif (( code >= 5 )); then verdict="maybe"; fi
    printf '%s %-28s %-5s %-8s %-10s %s\n' "$LOG_PREFIX" "$name" "$git" "$code" "${nm_size:-0}" "$verdict"
  done
}

# --------------------------------------------------------------------------
# Recommendations (pure function of the scan)
# --------------------------------------------------------------------------
recommend() {
  log "===== Scan report ====="
  log "OS/arch      : $OS / $ARCH_NORM"
  log "RAM          : ${RAM_GB} GB"
  log "Disk free    : ${DISK_GB} GB (${HOME})"
  log "Tools        : brew=$(has_tool brew && echo yes || echo no) node=$(has_tool node && echo yes || echo no) cargo=$(has_tool cargo && echo yes || echo no) python3=$(has_tool python3 && echo yes || echo no)"
  local agents="$AGENTS"; [[ -z "$agents" ]] && agents=" none detected"
  log "Agents       :$agents"
  log "OpenCode cfg : $CONFIG_FILE"
  log "Providers    : ${PROVIDERS:-none detected}"
  log ""

  log "===== Layer recommendations ====="
  log "Tier 0 (always)     : OpenCode compaction {auto, prune, reserved}"
  if [[ "$PROVIDERS" == *anthropic* ]]; then
    log "Tier 0 (cache)      : setCacheKey: true  (Anthropic prompt caching)"
  else
    log "Tier 0 (cache)      : setCacheKey n/a — provider '${PROVIDERS:-?}' does not use Anthropic caching"
  fi
  if command -v codebase-memory-mcp >/dev/null 2>&1 || [[ -x "$HOME/.local/bin/codebase-memory-mcp" ]]; then
    log "Tier 1 (graph)      : Codebase Memory MCP — already installed"
  else
    log "Tier 1 (graph)      : Codebase Memory MCP — INSTALL (needs curl)"
  fi
  if command -v rtk >/dev/null 2>&1; then
    log "Tier 1 (rtk)        : rtk — already installed"
  else
    local how=""; if has_tool brew; then how="brew install rtk"; elif has_tool cargo; then how="cargo install --git https://github.com/rtk-ai/rtk"; else how="download from github.com/rtk-ai/rtk releases"; fi
    log "Tier 1 (rtk)        : rtk — INSTALL via: $how"
  fi
  if (( RAM_GB >= 16 )); then
    log "Tier 2 (enforce)    : Token Optimizer MCP — suitable (RAM >= 16 GB) — MANUAL install (docs/token-optimization.md)"
  else
    log "Tier 2 (enforce)    : Token Optimizer MCP — SKIP (RAM ${RAM_GB} GB < 16 GB; node daemon too heavy)"
  fi
  if (( DISK_GB < 20 )); then
    warn "Low disk (${DISK_GB} GB free): index caches + node_modules + media can fill this fast. Clean up before installing."
  fi
  if (( RAM_GB >= 8 && DISK_GB >= 40 )); then
    log "Tier 3 (optional)   : caveman skill (npx skills add JuliusBrussee/caveman) + Context7 MCP — MANUAL"
  fi
  log ""
  if (( APPLY == 0 )); then
    log "Dry run — re-run with --apply to install Tier 0-1. Use --index <dir...> to index projects."
  fi
}

# --------------------------------------------------------------------------
# Tier 0/1 — merge OpenCode built-in settings + CBM MCP entry.
# Writes the config as plain JSON if anything changes (comments are removed —
# a timestamped backup is created first). Robust against // and /* */ comments
# and trailing commas in the source JSONC.
# --------------------------------------------------------------------------
apply_config() {
  [[ -d "$CONFIG_DIR" ]] || mkdir -p "$CONFIG_DIR"
  local merge_src='{
    "compaction": { "auto": true, "prune": true, "reserved": 10000 }
  }'
  # Only reference the CBM binary when it actually exists and is executable.
  if [[ -x "$HOME/.local/bin/codebase-memory-mcp" ]]; then
    merge_src='{
      "compaction": { "auto": true, "prune": true, "reserved": 10000 },
      "mcp": {
        "codebase-memory": {
          "type": "local",
          "command": ["'$HOME'/.local/bin/codebase-memory-mcp"]
        }
      }
    }'
  fi
  command -v python3 >/dev/null 2>&1 || die "python3 required to merge config"
  python3 - "$CONFIG_FILE" "$merge_src" <<'PYEOF'
import json, sys, os, shutil, time

def strip_jsonc(s):
    """Remove /* */ and // comments and trailing commas, string-aware."""
    out, i, n, state = [], 0, len(s), "code"
    while i < n:
        c = s[i]
        if state == "code":
            if c == '"':
                state = "str"; out.append(c)
            elif c == "/" and i + 1 < n and s[i+1] == "/":
                state = "line_comment"; i += 1
            elif c == "/" and i + 1 < n and s[i+1] == "*":
                state = "block_comment"; i += 1
            else:
                out.append(c)
        elif state == "str":
            out.append(c)
            if c == "\\" and i + 1 < n:
                out.append(s[i+1]); i += 1
            elif c == '"':
                state = "code"
        elif state == "line_comment":
            if c == "\n":
                state = "code"; out.append(c)
        elif state == "block_comment":
            if c == "*" and i + 1 < n and s[i+1] == "/":
                state = "code"; i += 1
        i += 1
    text = "".join(out)
    # drop trailing commas (outside strings), allowing whitespace before the brace
    res, i, n, in_str = [], 0, len(text), False
    while i < n:
        c = text[i]
        if c == '"' and (i == 0 or text[i-1] != "\\"):
            in_str = not in_str; res.append(c)
        elif c == "," and not in_str:
            j = i + 1
            while j < n and text[j] in " \t\r\n":
                j += 1
            if j < n and text[j] in "}]":
                pass  # trailing comma before closing brace -> drop
            else:
                res.append(c)
        else:
            res.append(c)
        i += 1
    return json.loads("".join(res))

def deep_merge(dst, src):
    for k, v in src.items():
        if isinstance(v, dict) and isinstance(dst.get(k), dict):
            deep_merge(dst[k], v)
        else:
            dst[k] = v
    return dst

path, merge_src = sys.argv[1], sys.argv[2]
merge = json.loads(merge_src)
if os.path.exists(path):
    with open(path) as f:
        data = strip_jsonc(f.read())
else:
    data = {"$schema": "https://opencode.ai/config.json"}
old = json.dumps(data, indent=2)
deep_merge(data, merge)
new = json.dumps(data, indent=2)
if old != new:
    if os.path.exists(path):
        bak = path + ".bak." + time.strftime("%Y%m%d%H%M%S")
        shutil.copy2(path, bak)
    with open(path, "w") as f:
        f.write(new + "\n")
    print("[token-stack] config updated:", path)
    print("[token-stack] NOTE: written as plain JSON (comments stripped). Backup:", bak)
else:
    print("[token-stack] config already up to date:", path)
PYEOF
}

# --------------------------------------------------------------------------
# Tier 1 — installs (idempotent)
# --------------------------------------------------------------------------
install_cbm() {
  if command -v codebase-memory-mcp >/dev/null 2>&1 || [[ -x "$HOME/.local/bin/codebase-memory-mcp" ]]; then
    log "Codebase Memory MCP already installed — skipping"
    return 0
  fi
  has_tool curl || die "curl required to install Codebase Memory MCP"
  log "Installing Codebase Memory MCP (single static binary for $OS/$ARCH_NORM)…"
  local tmp; tmp="$(mktemp)"
  # HTTPS-only, download fully BEFORE executing so a partial script can never run.
  if ! curl -fsSL --proto '=https' -o "$tmp" \
      https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh; then
    rm -f "$tmp"; die "download failed — check network or the upstream repo"
  fi
  bash "$tmp" && rm -f "$tmp" || { rm -f "$tmp"; die "install script failed"; }
  if ! [[ -x "$HOME/.local/bin/codebase-memory-mcp" ]]; then
    warn "binary not found at $HOME/.local/bin after install — check the installer output"
  fi
  log "Installed. If OpenCode was not auto-detected, the config merge adds the MCP entry."
}

install_rtk() {
  if command -v rtk >/dev/null 2>&1; then
    log "rtk already installed — skipping"
  else
    if has_tool brew; then
      log "Installing rtk via Homebrew…"; brew install rtk
    elif has_tool cargo; then
      log "Installing rtk via cargo (this may take a few minutes)…"
      cargo install --git https://github.com/rtk-ai/rtk
    else
      warn "No brew/cargo — install rtk manually from https://github.com/rtk-ai/rtk/releases"; return 0
    fi
  fi
  # Wire the OpenCode plugin when OpenCode is present
  if has_agent opencode; then
    if [[ -f "$PLUGIN_DIR/rtk.ts" ]]; then
      log "rtk OpenCode plugin already wired ($PLUGIN_DIR/rtk.ts)"
    else
      log "Wiring rtk OpenCode plugin…"
      RTK_TELEMETRY_DISABLED=1 rtk init -g --opencode < /dev/null >/dev/null 2>&1 \
        || warn "rtk init failed — run manually: rtk init -g --opencode"
      [[ -f "$PLUGIN_DIR/rtk.ts" ]] && log "Plugin written to $PLUGIN_DIR/rtk.ts (restart OpenCode)"
    fi
  else
    log "OpenCode not detected — run 'rtk init -g --opencode' after installing OpenCode"
  fi
}

# --------------------------------------------------------------------------
# Indexing helper
# --------------------------------------------------------------------------
index_projects() {
  local cbm=""
  if command -v codebase-memory-mcp >/dev/null 2>&1; then
    cbm="$(command -v codebase-memory-mcp)"
  elif [[ -x "$HOME/.local/bin/codebase-memory-mcp" ]]; then
    cbm="$HOME/.local/bin/codebase-memory-mcp"
  else
    die "Codebase Memory MCP not installed — run with --apply first"
  fi
  for dir in "${INDEX_DIRS[@]}"; do
    [[ -d "$dir" ]] || { warn "skip (not a directory): $dir"; continue; }
    log "Indexing $dir (fast mode)…"
    # `|| true` guards against SIGPIPE from head -1 closing the pipe (pipefail-safe)
    local out; out="$("$cbm" cli index_repository --repo-path "$dir" --mode fast 2>&1 \
      | grep -v '^level=' | head -1 || true)"
    log "${out:-indexed (no output)}"
  done
}

# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------
detect_os_arch
detect_ram_gb
detect_disk_free_gb
detect_tools
detect_agents
detect_opencode_config
detect_provider

if (( ${#INDEX_DIRS[@]} > 0 )); then
  # --index is exclusive; note if --apply was also passed
  if (( APPLY == 1 )); then
    warn "--index is exclusive — ignoring --apply for this run"
  fi
  index_projects
  exit 0
fi

recommend

if (( APPLY == 1 )); then
  log "===== Applying (Tier 0-1) ====="
  install_cbm
  install_rtk
  apply_config   # only adds the CBM MCP entry if the binary is executable
  log "Done. Restart OpenCode, then say \"index this project\" in each repo you work on."
  log "Tip: ./setup-token-stack.sh --index /path/to/project (or --projects <dir> to see all)"
fi

exit 0
