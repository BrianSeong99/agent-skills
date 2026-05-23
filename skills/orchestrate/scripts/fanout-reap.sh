#!/usr/bin/env bash
# Reap a finished fan-out entry: check whether the milestone's PR has merged,
# and update fanout-state.json accordingly.
#
# Usage: fanout-reap.sh <id>
#        fanout-reap.sh <id> --pr <number>     # explicit PR number
#        fanout-reap.sh <id> --abandon         # mark abandoned, do not check PR
#
# PR linkage:
#   If --pr is omitted, we look at /tmp/codex_<id>.log for the most recent line
#   matching `https://github.com/[^/]+/[^/]+/pull/<n>` and use that PR number.
#   We then call `gh pr view <n> --json state,mergedAt` to determine merged.
#
# Status transitions written:
#   running|stuck|exited  → completed   (PR merged)
#   running|stuck|exited  → exited-pr-open   (PR exists, not merged)
#   any                   → abandoned   (with --abandon)
#
# Env:
#   GH_REPO   optional   — pass through to `gh pr view` if needed.
set -euo pipefail

id="${1:-}"
shift || true

if [ -z "$id" ]; then
  echo "fanout-reap: usage: fanout-reap.sh <id> [--pr <n>] [--abandon]" >&2
  exit 2
fi

explicit_pr=""
abandon=false
while [ $# -gt 0 ]; do
  case "$1" in
    --pr) explicit_pr="${2:-}"; shift 2 ;;
    --abandon) abandon=true; shift ;;
    *) echo "fanout-reap: unknown arg: $1" >&2; exit 2 ;;
  esac
done

state_dir="$HOME/.claude/orchestrate"
state_file="$state_dir/fanout-state.json"

if [ ! -f "$state_file" ]; then
  echo "fanout-reap: no state file at $state_file" >&2
  exit 1
fi

entry=$(jq -c --arg id "$id" '.[] | select(.id == $id)' "$state_file" | head -n 1)
if [ -z "$entry" ]; then
  echo "fanout-reap: id '$id' not in $state_file" >&2
  exit 1
fi

if [ "$abandon" = true ]; then
  new_status="abandoned"
  pr_number=""
  merged="false"
else
  log=$(printf '%s' "$entry" | jq -r '.log // ""')
  pr_number="$explicit_pr"

  if [ -z "$pr_number" ] && [ -f "$log" ]; then
    # Last PR URL mentioned in the codex log wins.
    pr_number=$(grep -oE 'github\.com/[^/]+/[^/]+/pull/[0-9]+' "$log" 2>/dev/null \
      | tail -1 | grep -oE '[0-9]+$' || true)
  fi

  if [ -z "$pr_number" ]; then
    new_status="exited"
    merged="false"
  else
    if ! command -v gh >/dev/null 2>&1; then
      echo "fanout-reap: gh CLI not on PATH; can't check PR #$pr_number" >&2
      new_status="exited"
      merged="false"
    else
      pr_json=$(gh pr view "$pr_number" --json state,mergedAt 2>/dev/null || true)
      if [ -z "$pr_json" ]; then
        new_status="exited"
        merged="false"
      else
        state=$(printf '%s' "$pr_json" | jq -r '.state // empty')
        if [ "$state" = "MERGED" ]; then
          new_status="completed"
          merged="true"
        else
          new_status="exited-pr-open"
          merged="false"
        fi
      fi
    fi
  fi
fi

reaped_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

tmp=$(mktemp)
jq --arg id "$id" \
   --arg status "$new_status" \
   --arg ts "$reaped_ts" \
   --arg pr "$pr_number" \
   --argjson merged "$merged" \
   'map(if .id == $id
        then . + {status: $status, reaped_ts: $ts, pr_number: $pr, pr_merged: $merged}
        else . end)' "$state_file" > "$tmp"
mv "$tmp" "$state_file"

jq -nc \
  --arg id "$id" \
  --arg status "$new_status" \
  --arg pr "$pr_number" \
  --argjson merged "$merged" \
  '{id:$id, status:$status, pr_number:$pr, pr_merged:$merged}'
