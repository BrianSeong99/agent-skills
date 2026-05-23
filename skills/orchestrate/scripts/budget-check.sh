#!/usr/bin/env bash
# Sum estimated cost in USD for a given task_hash from runs.jsonl.
#
# Usage:
#   budget-check.sh <task_hash>                       # print total spent for this task
#   budget-check.sh <task_hash> --check               # exit 0 if under cap, 1 if over
#   budget-check.sh <task_hash> --estimate <usd>      # check whether spent+estimate fits
#
# Cap source:
#   ORCHESTRATE_BUDGET_USD env var. Unset = no cap; --check always returns 0.
#
# Output (stdout, JSON):
#   {"task_hash":"<h>","spent_usd":<f>,"cap_usd":<f|null>,"would_be_usd":<f>,"ok":<bool>}
#
# Notes:
#   - Reads ~/.claude/orchestrate/runs.jsonl. If a row is missing
#     `cost_usd_estimate`, it contributes 0 — V1.5 entries are backward-compatible.
#   - The estimate is a guardrail, not accounting. Brief over/undershoot is fine.
set -euo pipefail

task_hash="${1:-}"
shift || true

if [ -z "$task_hash" ]; then
  echo "budget-check: usage: budget-check.sh <task_hash> [--check] [--estimate <usd>]" >&2
  exit 2
fi

mode="report"
estimate=0
while [ $# -gt 0 ]; do
  case "$1" in
    --check) mode="check"; shift ;;
    --estimate) estimate="${2:-0}"; shift 2 ;;
    *) echo "budget-check: unknown arg: $1" >&2; exit 2 ;;
  esac
done

runs="$HOME/.claude/orchestrate/runs.jsonl"
cap="${ORCHESTRATE_BUDGET_USD:-}"

spent=0
if [ -f "$runs" ] && [ -s "$runs" ]; then
  # Slurp the JSONL into an array, sum cost_usd_estimate for matching task_hash.
  spent=$(jq -s --arg th "$task_hash" \
    '[.[] | select(.task_hash == $th) | (.cost_usd_estimate // 0)] | add // 0' \
    "$runs" 2>/dev/null || echo 0)
  if [ -z "$spent" ] || [ "$spent" = "null" ]; then
    spent=0
  fi
fi

would_be=$(awk -v s="$spent" -v e="$estimate" 'BEGIN { printf "%.6f", s + e }')

if [ -z "$cap" ]; then
  ok=true
  cap_json="null"
else
  cap_json="$cap"
  # awk to handle floating-point compare cleanly
  ok=$(awk -v w="$would_be" -v c="$cap" 'BEGIN { print (w <= c) ? "true" : "false" }')
fi

jq -nc \
  --arg th "$task_hash" \
  --argjson spent "$spent" \
  --argjson would_be "$would_be" \
  --argjson ok "$ok" \
  --argjson cap "$cap_json" \
  '{task_hash:$th, spent_usd:$spent, cap_usd:$cap, would_be_usd:$would_be, ok:$ok}'

if [ "$mode" = "check" ]; then
  [ "$ok" = "true" ]
fi
