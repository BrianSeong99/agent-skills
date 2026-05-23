#!/usr/bin/env bash
# Reverse install-hook.sh: remove orchestrate's PostToolUse hook from
# ~/.claude/settings.json. Leaves other hook entries alone.
#
# Usage:
#   uninstall-hook.sh            # remove the orchestrate-marked hook
#   uninstall-hook.sh --dry-run  # print what would be written
set -euo pipefail

dry_run=false
case "${1:-}" in
  --dry-run) dry_run=true ;;
  -h|--help) sed -n 's/^# \{0,1\}//p' "$0" | sed -n '1,10p'; exit 0 ;;
  "") ;;
  *) echo "uninstall-hook: unknown arg: $1" >&2; exit 2 ;;
esac

settings="$HOME/.claude/settings.json"
marker="orchestrate-stuck-loop"

if [ ! -f "$settings" ]; then
  echo "uninstall-hook: $settings does not exist; nothing to do."
  exit 0
fi

if ! jq -e '.' "$settings" >/dev/null 2>&1; then
  echo "uninstall-hook: $settings is not valid JSON; refusing to touch." >&2
  exit 1
fi

updated=$(jq --arg marker "$marker" '
  if (.hooks.PostToolUse // []) | type == "array" then
    .hooks.PostToolUse |= map(
      .hooks |= ((. // []) | map(select(._orchestrate_marker != $marker)))
    )
    | .hooks.PostToolUse |= map(select((.hooks // []) | length > 0))
    | if (.hooks.PostToolUse | length) == 0 then del(.hooks.PostToolUse) else . end
    | if (.hooks // {}) == {} then del(.hooks) else . end
  else . end
' "$settings")

if [ "$dry_run" = true ]; then
  printf '%s\n' "$updated" | jq '.'
  exit 0
fi

tmp=$(mktemp)
printf '%s\n' "$updated" | jq '.' > "$tmp"
mv "$tmp" "$settings"

echo "uninstall-hook: removed orchestrate hook from $settings"
