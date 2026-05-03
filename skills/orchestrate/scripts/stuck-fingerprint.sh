#!/usr/bin/env bash
# PostToolUse hook payload handler for orchestrate's stuck-loop detector.
#
# Reads the hook JSON event from stdin, fingerprints (tool, args, result_hash),
# pushes onto a rolling window of the last 3 calls in
# ~/.claude/orchestrate/stuck-window.jsonl. If all 3 fingerprints match, writes
# a warning line into ~/.claude/orchestrate/stuck.log and prints a single
# decision JSON object on stdout that surfaces the warning to Claude Code.
#
# This script is referenced by the PostToolUse entry installed via
# install-hook.sh; per anthropics/claude-code#19225, hook entries cannot live
# inside SKILL.md and must be in ~/.claude/settings.json.
#
# Hook event payload (subset we care about):
#   { "tool_name": "...", "tool_input": {...}, "tool_response": {...}, ... }
#
# Output: a JSON decision object on stdout. Empty {} when nothing to do.
set -euo pipefail

state_dir="$HOME/.claude/orchestrate"
mkdir -p "$state_dir"
window_file="$state_dir/stuck-window.jsonl"
warn_file="$state_dir/stuck.log"

# Read the hook event from stdin (best-effort; if no JSON, exit silently).
event=$(cat || true)
if [ -z "$event" ]; then
  echo '{}'
  exit 0
fi
if ! printf '%s' "$event" | jq -e '.' >/dev/null 2>&1; then
  echo '{}'
  exit 0
fi

tool=$(printf '%s' "$event" | jq -r '.tool_name // empty')
if [ -z "$tool" ]; then
  echo '{}'
  exit 0
fi

# Fingerprint = sha256 of (tool || canonical(args) || sha256(result_truncated))
args_canon=$(printf '%s' "$event" | jq -Sc '.tool_input // {}')
result_blob=$(printf '%s' "$event" | jq -Sc '.tool_response // {}' | head -c 4096)
result_hash=$(printf '%s' "$result_blob" | shasum -a 256 | cut -c1-16)
fingerprint=$(printf '%s|%s|%s' "$tool" "$args_canon" "$result_hash" | shasum -a 256 | cut -c1-16)

ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
entry=$(jq -nc --arg ts "$ts" --arg tool "$tool" --arg fp "$fingerprint" \
  '{ts:$ts, tool:$tool, fp:$fp}')

# Append, then truncate window to last 3 lines.
printf '%s\n' "$entry" >> "$window_file"
tmp=$(mktemp)
tail -n 3 "$window_file" > "$tmp"
mv "$tmp" "$window_file"

# Count distinct fingerprints in the window.
line_count=$(wc -l < "$window_file" | tr -d ' ')
distinct=$(awk '{print}' "$window_file" | jq -r '.fp' | sort -u | wc -l | tr -d ' ')

decision='{}'
if [ "$line_count" -ge 3 ] && [ "$distinct" -eq 1 ]; then
  msg="orchestrate stuck-loop detector: 3 identical $tool calls in a row (fp=$fingerprint). Consider stopping or changing approach."
  printf '%s %s\n' "$ts" "$msg" >> "$warn_file"
  decision=$(jq -nc --arg msg "$msg" '{
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      additionalContext: $msg
    }
  }')
  # Reset the window so we warn once per streak, not on every tool call after.
  : > "$window_file"
fi

printf '%s\n' "$decision"
