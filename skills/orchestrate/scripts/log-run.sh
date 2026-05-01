#!/usr/bin/env bash
# Append one run record (one JSON line) to ~/.claude/orchestrate/runs.jsonl.
# Usage: log-run.sh '<json-object>'
#        echo '<json-object>' | log-run.sh
# Adds a `ts` field (UTC ISO8601) if not already present.
# Required keys (caller must supply): category, backend, ok
# Recommended:                        model, walltime_s, task_hash, error
set -euo pipefail

state_dir="$HOME/.claude/orchestrate"
mkdir -p "$state_dir"
out="$state_dir/runs.jsonl"

input="${1:-}"
if [ -z "$input" ]; then
  input=$(cat)
fi
if [ -z "$input" ]; then
  echo "log-run: empty input" >&2
  exit 2
fi

# Validate JSON
if ! printf '%s' "$input" | jq -e '.' >/dev/null 2>&1; then
  echo "log-run: input is not valid JSON" >&2
  exit 2
fi

# Validate required keys
missing=$(printf '%s' "$input" | jq -r '
  ["category","backend","ok"] - [keys[]] | join(",")
')
if [ -n "$missing" ]; then
  echo "log-run: missing required keys: $missing" >&2
  exit 2
fi

ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
printf '%s' "$input" | jq -c --arg ts "$ts" '. + (if has("ts") then {} else {ts:$ts} end)' >> "$out"
