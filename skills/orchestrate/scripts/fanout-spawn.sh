#!/usr/bin/env bash
# Spawn one codex run in the background as part of a fan-out batch.
# Records the run in ~/.claude/orchestrate/fanout-state.json so fanout-check.sh
# and fanout-reap.sh can reason about the cohort later.
#
# Usage: fanout-spawn.sh <id> <prompt-file>
#   <id>           — short label for the run (e.g. M4.32). Used for log path,
#                    state-file key, and PR linkage. Keep it filename-safe.
#   <prompt-file>  — path to a file containing the full brief for codex.
#
# Behavior:
#   - Refuses to spawn if ORCHESTRATE_FANOUT_CAP (default 4) is already in flight.
#   - Refuses to spawn if `<id>` already exists in state with status=running.
#   - Refuses to spawn if codex preflight is not ok (uses cached preflight.json).
#   - Streams codex stdout/stderr into /tmp/codex_<id>.log.
#   - Writes a {"id","pid","log","prompt","spawned_ts","status":"running"}
#     entry into ~/.claude/orchestrate/fanout-state.json (array of objects).
#
# Env:
#   ORCHESTRATE_FANOUT_CAP   default 4    — max concurrent runs.
#   CODEX_PLUGIN_ROOT        autodetect   — see preflight.sh.
#   ORCHESTRATE_FANOUT_NOOP  unset        — if set, skip actually launching codex
#                                            (for smoke tests). Still writes state.
set -euo pipefail

id="${1:-}"
prompt_file="${2:-}"

if [ -z "$id" ] || [ -z "$prompt_file" ]; then
  echo "fanout-spawn: usage: fanout-spawn.sh <id> <prompt-file>" >&2
  exit 2
fi

# id must be filename-safe — codex log path is built from it.
if ! printf '%s' "$id" | grep -qE '^[A-Za-z0-9._-]+$'; then
  echo "fanout-spawn: id must match [A-Za-z0-9._-]+ (got: $id)" >&2
  exit 2
fi

if [ ! -f "$prompt_file" ]; then
  echo "fanout-spawn: prompt file not found: $prompt_file" >&2
  exit 2
fi

state_dir="$HOME/.claude/orchestrate"
mkdir -p "$state_dir"
state_file="$state_dir/fanout-state.json"
log_path="/tmp/codex_${id}.log"

cap="${ORCHESTRATE_FANOUT_CAP:-4}"

# Initialize state file if missing
if [ ! -f "$state_file" ]; then
  echo '[]' > "$state_file"
fi

# Validate state file is a JSON array
if ! jq -e 'type == "array"' "$state_file" >/dev/null 2>&1; then
  echo "fanout-spawn: $state_file is not a JSON array; refusing to clobber" >&2
  exit 2
fi

# Reject duplicate id with status=running.
if jq -e --arg id "$id" '.[] | select(.id == $id and .status == "running")' "$state_file" >/dev/null 2>&1; then
  echo "fanout-spawn: id '$id' already running. Reap or remove it first." >&2
  exit 1
fi

# Count currently-running entries
running_count=$(jq '[.[] | select(.status == "running")] | length' "$state_file")
if [ "$running_count" -ge "$cap" ]; then
  echo "fanout-spawn: at fan-out cap ($running_count/$cap). Wait for some to finish or raise ORCHESTRATE_FANOUT_CAP." >&2
  exit 1
fi

# Preflight gate — only enforced when not in NOOP smoke-test mode.
if [ -z "${ORCHESTRATE_FANOUT_NOOP:-}" ]; then
  preflight_json="$state_dir/preflight.json"
  if [ ! -f "$preflight_json" ]; then
    bash "$(dirname "$0")/../preflight.sh" >/dev/null 2>&1 || true
  fi
  if [ -f "$preflight_json" ] && ! jq -e '.codex.ok == true' "$preflight_json" >/dev/null 2>&1; then
    msg=$(jq -r '.codex.msg // "codex not ready"' "$preflight_json")
    echo "fanout-spawn: codex preflight not ok: $msg" >&2
    exit 1
  fi
fi

# Resolve codex companion path (same logic as preflight.sh)
codex_root="${CODEX_PLUGIN_ROOT:-}"
if [ -z "$codex_root" ]; then
  codex_root=$(ls -1d "$HOME"/.claude/plugins/cache/openai-codex/codex/*/ 2>/dev/null | sort -V | tail -1 | sed 's:/*$::' || true)
fi

spawned_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

if [ -n "${ORCHESTRATE_FANOUT_NOOP:-}" ]; then
  # Smoke-test mode: write a marker line into the log, no codex spawn.
  printf 'NOOP fanout spawn: id=%s prompt=%s ts=%s\n' "$id" "$prompt_file" "$spawned_ts" > "$log_path"
  pid="$$"  # placeholder
else
  if [ -z "$codex_root" ] || [ ! -f "${codex_root%/}/scripts/codex-companion.mjs" ]; then
    echo "fanout-spawn: codex plugin not installed. Run preflight.sh for the fix command." >&2
    exit 1
  fi
  # Background codex exec, full-auto. Detach with setsid so the job survives
  # the parent shell. nohup is portable; setsid not on macOS by default.
  : > "$log_path"
  ( nohup codex exec --full-auto --skip-git-repo-check < "$prompt_file" >>"$log_path" 2>&1 ) &
  pid=$!
  disown "$pid" 2>/dev/null || true
fi

# Atomic state update via jq (load → mutate → write tmp → mv)
tmp=$(mktemp)
jq --arg id "$id" \
   --arg log "$log_path" \
   --arg prompt "$prompt_file" \
   --arg ts "$spawned_ts" \
   --argjson pid "$pid" \
   '. + [{
     id: $id,
     pid: $pid,
     log: $log,
     prompt: $prompt,
     spawned_ts: $ts,
     status: "running"
   }]' "$state_file" > "$tmp"
mv "$tmp" "$state_file"

# Emit a one-line confirmation on stdout for the caller
jq -nc \
  --arg id "$id" \
  --arg log "$log_path" \
  --arg ts "$spawned_ts" \
  --argjson pid "$pid" \
  '{id:$id, pid:$pid, log:$log, spawned_ts:$ts, status:"running"}'
