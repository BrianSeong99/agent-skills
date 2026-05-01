#!/usr/bin/env bash
# Preflight: confirm Codex CLI + Ollama are usable. Cache result for 5min.
# Usage: preflight.sh           # cached if fresh
#        preflight.sh --force   # bypass cache
# Stdout: a single JSON object {ts, codex:{ok,msg}, ollama:{ok,msg}}
#
# Env overrides:
#   ORCHESTRATE_DISABLED_BACKENDS  # comma-separated: codex,ollama (mark as not-ok with msg)
#   OLLAMA_URL                     # default http://localhost:11434
#   OLLAMA_MODEL                   # default gemma3:4b
#   CODEX_PLUGIN_ROOT              # override autodiscovery if you've moved the plugin
set -euo pipefail

state_dir="$HOME/.claude/orchestrate"
mkdir -p "$state_dir"
out="$state_dir/preflight.json"

# Cache hit (5min TTL) unless --force
if [ "${1:-}" != "--force" ] && [ -f "$out" ]; then
  age=$(( $(date +%s) - $(stat -f %m "$out" 2>/dev/null || stat -c %Y "$out") ))
  if [ "$age" -lt 300 ]; then
    cat "$out"
    exit 0
  fi
fi

ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

disabled="${ORCHESTRATE_DISABLED_BACKENDS:-}"
is_disabled() {
  case ",$disabled," in *",$1,"*) return 0 ;; *) return 1 ;; esac
}

# 1. Codex
codex_ok=false
codex_msg=""

if is_disabled codex; then
  codex_msg="disabled by user (ORCHESTRATE_DISABLED_BACKENDS)"
else
  # Auto-discover codex plugin path. Honors $CODEX_PLUGIN_ROOT override; otherwise
  # globs the cache dir and picks the highest version (sort -V).
  codex_root="${CODEX_PLUGIN_ROOT:-}"
  if [ -z "$codex_root" ]; then
    codex_root=$(ls -1d "$HOME"/.claude/plugins/cache/openai-codex/codex/*/ 2>/dev/null | sort -V | tail -1 | sed 's:/*$::' || true)
  fi
  codex_companion="${codex_root%/}/scripts/codex-companion.mjs"

  if [ -z "$codex_root" ] || [ ! -f "$codex_companion" ]; then
    codex_msg="codex plugin not installed (looked under ~/.claude/plugins/cache/openai-codex/codex/). Install via the codex@openai-codex plugin marketplace."
  elif ! command -v node >/dev/null 2>&1; then
    codex_msg="node not on PATH — codex-companion needs node (>=18 recommended)"
  else
    setup_out=$(node "$codex_companion" setup --json 2>&1) || true
    if printf '%s' "$setup_out" | jq -e '.ready == true' >/dev/null 2>&1; then
      codex_ok=true
    else
      short=$(printf '%s' "$setup_out" | head -c 240 | tr '\n' ' ')
      codex_msg="codex setup not ready: ${short:-unknown error}. Try: !codex login"
    fi
  fi
fi

# 2. Ollama (lenient: daemon up = ok; missing model is a warning, not a hard fail)
ollama_ok=false
ollama_msg=""

if is_disabled ollama; then
  ollama_msg="disabled by user (ORCHESTRATE_DISABLED_BACKENDS)"
else
  ollama_url="${OLLAMA_URL:-http://localhost:11434}"
  ollama_model="${OLLAMA_MODEL:-gemma3:4b}"
  tags_tmp=$(mktemp)
  http_code=$(curl -s --max-time 5 -o "$tags_tmp" -w "%{http_code}" "$ollama_url/api/tags" 2>/dev/null || echo "000")
  if [ "$http_code" = "200" ]; then
    if jq -e --arg m "$ollama_model" '.models[]? | select(.name == $m)' "$tags_tmp" >/dev/null 2>&1; then
      ollama_ok=true
    else
      # daemon up, but configured model isn't pulled. Still ok=true (you can route to it
      # and ollama will autopull on first call), but include a hint.
      ollama_ok=true
      ollama_msg="ollama daemon up; model '$ollama_model' not pulled yet. First call will autopull, or run: ollama pull $ollama_model"
    fi
  else
    ollama_msg="ollama daemon unreachable at $ollama_url (http=$http_code). Run: brew services start ollama (macOS) or systemctl start ollama (linux)"
  fi
  rm -f "$tags_tmp"
fi

jq -nc \
  --arg ts "$ts" \
  --argjson codex_ok "$codex_ok" --arg codex_msg "$codex_msg" \
  --argjson ollama_ok "$ollama_ok" --arg ollama_msg "$ollama_msg" \
  '{ts:$ts, codex:{ok:$codex_ok, msg:$codex_msg}, ollama:{ok:$ollama_ok, msg:$ollama_msg}}' \
  | tee "$out"
