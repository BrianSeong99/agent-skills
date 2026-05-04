#!/usr/bin/env bash
# install.sh — symlink skills from this repo into Claude Code AND Codex CLI skill dirs.
#
# Usage:
#   ./install.sh <skill-name>...    # install named skills (to all detected target dirs)
#   ./install.sh --all              # install every skill in skills/
#   ./install.sh --list             # list available skills
#   ./install.sh --uninstall <name> # remove from all target dirs
#
# Targets are auto-detected. A skill is symlinked into every dir that exists:
#   ~/.claude/skills/<name>   (Claude Code)   — when ~/.claude exists
#   ~/.codex/skills/<name>    (Codex CLI)     — when ~/.codex exists
#
# Skill state (logs, preflight cache, etc.) lives at ~/.claude/<name>/ regardless
# of which agent invokes the skill — both agents read/write the same state.
#
# Idempotent — re-running refreshes the symlinks.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skills_src="$repo_root/skills"

# Detect target skill dirs. One line per target: <agent>:<skills-dir>
detect_targets() {
  [ -d "$HOME/.claude" ] && printf 'claude:%s/.claude/skills\n' "$HOME"
  [ -d "$HOME/.codex"  ] && printf 'codex:%s/.codex/skills\n'  "$HOME"
}

usage() {
  sed -n 's/^# //p' "$0" | sed -n '1,16p'
  exit "${1:-0}"
}

list_skills() {
  if [ ! -d "$skills_src" ]; then
    echo "no skills/ directory found in $repo_root" >&2
    exit 1
  fi
  for d in "$skills_src"/*/; do
    [ -d "$d" ] || continue
    name=$(basename "$d")
    desc=""
    if [ -f "$d/SKILL.md" ]; then
      desc=$(awk '/^description:/{sub(/^description:[[:space:]]*/,""); print; exit}' "$d/SKILL.md" | head -c 120)
    fi
    printf '  %-24s %s\n' "$name" "$desc"
  done
}

install_one() {
  local name="$1"
  local src="$skills_src/$name"

  if [ ! -d "$src" ]; then
    echo "✗ $name — not found in $skills_src" >&2
    return 1
  fi
  if [ ! -f "$src/SKILL.md" ]; then
    echo "✗ $name — missing SKILL.md" >&2
    return 1
  fi

  local targets installed=0
  targets=$(detect_targets)
  if [ -z "$targets" ]; then
    echo "✗ no target dirs detected — neither ~/.claude nor ~/.codex exists" >&2
    return 1
  fi

  while IFS=: read -r agent dst_root; do
    [ -n "${agent:-}" ] || continue
    mkdir -p "$dst_root"
    local dst="$dst_root/$name"
    if [ -e "$dst" ] && [ ! -L "$dst" ]; then
      echo "✗ $name → $agent — $dst exists and is not a symlink; skipping" >&2
      continue
    fi
    ln -sfn "$src" "$dst"
    echo "✓ $name → $dst"
    installed=$((installed + 1))
  done <<< "$targets"

  # Per-skill state dir (single source of truth at ~/.claude/<name>/)
  mkdir -p "$HOME/.claude/$name"

  # Run preflight if the skill ships one
  if [ "$installed" -gt 0 ] && [ -x "$src/preflight.sh" ]; then
    "$src/preflight.sh" --force >/dev/null 2>&1 || true
    echo "  preflight ran (cached at ~/.claude/$name/preflight.json)"
  fi
}

uninstall_one() {
  local name="$1"
  local removed=0
  while IFS=: read -r agent dst_root; do
    [ -n "${agent:-}" ] || continue
    local dst="$dst_root/$name"
    if [ -L "$dst" ]; then
      rm "$dst"
      echo "✓ removed symlink $dst"
      removed=$((removed + 1))
    elif [ -e "$dst" ]; then
      echo "✗ $dst exists but isn't a symlink — refusing to delete. Inspect manually." >&2
    fi
  done <<< "$(detect_targets)"
  if [ "$removed" -eq 0 ]; then
    echo "  $name not installed (nothing to remove from any target; state dir ~/.claude/$name preserved)"
  fi
}

if [ $# -eq 0 ]; then usage 1; fi

case "$1" in
  --help|-h)        usage 0 ;;
  --list)           list_skills ;;
  --all)
    for d in "$skills_src"/*/; do
      [ -d "$d" ] || continue
      install_one "$(basename "$d")" || true
    done
    ;;
  --uninstall)
    shift
    [ $# -gt 0 ] || { echo "--uninstall needs a skill name" >&2; exit 1; }
    for n in "$@"; do uninstall_one "$n"; done
    ;;
  *)
    for n in "$@"; do install_one "$n"; done
    ;;
esac
