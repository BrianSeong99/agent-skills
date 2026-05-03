#!/usr/bin/env bash
# Report status for every entry in fanout-state.json.
# Stdout: a JSON array of objects, one per id, with current liveness assessment.
#
# Usage: fanout-check.sh             # all entries
#        fanout-check.sh <id>        # filter to one id
#
# Stuck detection:
#   A run is "stuck" when its status is "running", its log file exists, and
#   the log's mtime is older than ORCHESTRATE_STUCK_AFTER_S (default 300s = 5min).
#   This is a heuristic — fanout-check NEVER kills a run. It just flags.
#
# Status values returned (per entry):
#   running        — pid alive, log fresh
#   stuck          — pid alive, log mtime older than threshold
#   exited         — pid no longer alive, status had been "running" (caller
#                    can run fanout-reap.sh to mark completed)
#   completed      — fanout-reap.sh has confirmed the PR is merged
#   abandoned      — manual mark for runs the user gave up on
#
# Env:
#   ORCHESTRATE_STUCK_AFTER_S   default 300
set -euo pipefail

filter_id="${1:-}"
state_dir="$HOME/.claude/orchestrate"
state_file="$state_dir/fanout-state.json"
threshold="${ORCHESTRATE_STUCK_AFTER_S:-300}"

if [ ! -f "$state_file" ]; then
  echo '[]'
  exit 0
fi

if ! jq -e 'type == "array"' "$state_file" >/dev/null 2>&1; then
  echo "fanout-check: $state_file is not a JSON array" >&2
  exit 2
fi

now=$(date +%s)

# stat -f %m on macOS, stat -c %Y on linux
mtime() {
  if [ -f "$1" ]; then
    stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0
  else
    echo 0
  fi
}

pid_alive() {
  local pid="$1"
  [ -n "$pid" ] && [ "$pid" -gt 0 ] 2>/dev/null && kill -0 "$pid" 2>/dev/null
}

# Build the augmented array entry-by-entry. jq is the cleanest tool but
# checking pid liveness needs the shell, so we drive jq from a loop.
out='[]'
count=$(jq 'length' "$state_file")
i=0
while [ "$i" -lt "$count" ]; do
  entry=$(jq -c --argjson i "$i" '.[$i]' "$state_file")
  id=$(printf '%s' "$entry" | jq -r '.id')

  if [ -n "$filter_id" ] && [ "$id" != "$filter_id" ]; then
    i=$((i + 1))
    continue
  fi

  status=$(printf '%s' "$entry" | jq -r '.status')
  pid=$(printf '%s' "$entry" | jq -r '.pid // 0')
  log=$(printf '%s' "$entry" | jq -r '.log // ""')

  computed="$status"
  age=0
  stuck_flagged=false

  if [ "$status" = "running" ]; then
    if pid_alive "$pid"; then
      log_mtime=$(mtime "$log")
      if [ "$log_mtime" -gt 0 ]; then
        age=$(( now - log_mtime ))
        if [ "$age" -ge "$threshold" ]; then
          computed="stuck"
          stuck_flagged=true
        fi
      fi
    else
      computed="exited"
    fi
  fi

  augmented=$(printf '%s' "$entry" | jq -c \
    --arg computed "$computed" \
    --argjson age "$age" \
    --argjson stuck "$stuck_flagged" \
    '. + {computed_status: $computed, log_age_s: $age, stuck_flagged: $stuck}')

  out=$(printf '%s' "$out" | jq -c --argjson e "$augmented" '. + [$e]')
  i=$((i + 1))
done

printf '%s\n' "$out"
