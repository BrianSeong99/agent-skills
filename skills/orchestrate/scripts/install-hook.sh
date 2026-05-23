#!/usr/bin/env bash
# Install orchestrate's stuck-loop PostToolUse hook into ~/.claude/settings.json.
#
# Why a script instead of inline in SKILL.md:
#   anthropics/claude-code#19225 — Stop/PostToolUse hook entries inside
#   SKILL.md don't fire. The hook MUST be in ~/.claude/settings.json. So we
#   ship an idempotent installer here.
#
# Usage:
#   install-hook.sh             # install / update the hook entry
#   install-hook.sh --dry-run   # print the JSON we would write, don't touch settings.json
#   install-hook.sh --force     # replace existing orchestrate hook entry
#
# Idempotent: re-running with no flag is a no-op if the hook is already present
# and points at the right script. With --force we overwrite the matchers/command.
set -euo pipefail

dry_run=false
force=false
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry_run=true; shift ;;
    --force) force=true; shift ;;
    -h|--help) sed -n 's/^# \{0,1\}//p' "$0" | sed -n '1,18p'; exit 0 ;;
    *) echo "install-hook: unknown arg: $1" >&2; exit 2 ;;
  esac
done

settings="$HOME/.claude/settings.json"
mkdir -p "$(dirname "$settings")"

# Marker we use to recognize our own entry across re-runs.
marker="orchestrate-stuck-loop"

# Resolve hook script path. Prefer the installed symlink at ~/.claude/skills,
# fall back to this worktree if invoked from there before install.
hook_script_installed="$HOME/.claude/skills/orchestrate/scripts/stuck-fingerprint.sh"
hook_script_local="$(cd "$(dirname "$0")" && pwd)/stuck-fingerprint.sh"
if [ -e "$hook_script_installed" ]; then
  hook_command="bash $hook_script_installed"
else
  hook_command="bash $hook_script_local"
fi

# Build the new hook entry. Use the matcher form so it applies to all tools.
new_hook=$(jq -nc \
  --arg cmd "$hook_command" \
  --arg marker "$marker" \
  '{
     matcher: "*",
     hooks: [
       {
         type: "command",
         command: $cmd,
         _orchestrate_marker: $marker,
         timeout: 10
       }
     ]
   }')

# Load existing settings (default to {}).
if [ -f "$settings" ]; then
  existing=$(cat "$settings")
  if ! printf '%s' "$existing" | jq -e '.' >/dev/null 2>&1; then
    echo "install-hook: $settings is not valid JSON; refusing to clobber" >&2
    exit 1
  fi
else
  existing='{}'
fi

# Compose new settings JSON: ensure .hooks.PostToolUse is an array, and
# either add or replace the orchestrate entry.
updated=$(printf '%s' "$existing" | jq \
  --argjson new "$new_hook" \
  --arg marker "$marker" \
  --argjson force "$( [ "$force" = true ] && echo true || echo false )" \
  '
  .hooks //= {}
  | .hooks.PostToolUse //= []
  | (.hooks.PostToolUse | map(.hooks // []) | add // []
       | map(._orchestrate_marker == $marker)
       | any) as $present
  | if $present and ($force | not) then
      .
    else
      .hooks.PostToolUse |= (
        map(select(
          (.hooks // []) | map(._orchestrate_marker == $marker) | any | not
        )) + [$new]
      )
    end
  ')

if [ "$dry_run" = true ]; then
  printf '%s\n' "$updated" | jq '.'
  exit 0
fi

# Write back atomically.
tmp=$(mktemp)
printf '%s\n' "$updated" | jq '.' > "$tmp"
mv "$tmp" "$settings"

echo "install-hook: PostToolUse hook installed in $settings (command: $hook_command)"
