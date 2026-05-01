#!/usr/bin/env bash
# install.sh — symlink one or more skills from this repo into ~/.claude/skills/
#
# Usage:
#   ./install.sh <skill-name>...    # install named skills
#   ./install.sh --all              # install every skill in skills/
#   ./install.sh --list             # list available skills
#   ./install.sh --uninstall <name> # remove a previously installed symlink
#
# Idempotent — re-running refreshes the symlinks.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skills_src="$repo_root/skills"
skills_dst="$HOME/.claude/skills"

usage() {
  sed -n 's/^# //p' "$0" | sed -n '1,12p'
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
  local dst="$skills_dst/$name"

  if [ ! -d "$src" ]; then
    echo "✗ $name — not found in $skills_src" >&2
    return 1
  fi
  if [ ! -f "$src/SKILL.md" ]; then
    echo "✗ $name — missing SKILL.md" >&2
    return 1
  fi

  mkdir -p "$skills_dst"

  # If destination exists and is a regular dir/file, refuse (don't clobber user's work)
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    echo "✗ $name — $dst exists and is not a symlink. Move it aside first." >&2
    return 1
  fi

  ln -sfn "$src" "$dst"

  # Per-skill state dir
  mkdir -p "$HOME/.claude/$name"

  echo "✓ $name → $dst"

  # Run preflight if the skill ships one
  if [ -x "$src/preflight.sh" ]; then
    "$src/preflight.sh" --force >/dev/null 2>&1 || true
    echo "  preflight ran (cached at ~/.claude/$name/preflight.json)"
  fi
}

uninstall_one() {
  local name="$1"
  local dst="$skills_dst/$name"
  if [ -L "$dst" ]; then
    rm "$dst"
    echo "✓ removed symlink $dst (state dir ~/.claude/$name preserved)"
  elif [ -e "$dst" ]; then
    echo "✗ $dst exists but isn't a symlink — refusing to delete. Inspect manually." >&2
    return 1
  else
    echo "  $name not installed (nothing to remove)"
  fi
}

if [ $# -eq 0 ]; then usage 1; fi

case "$1" in
  --help|-h)        usage 0 ;;
  --list)           list_skills ;;
  --all)
    for d in "$skills_src"/*/; do
      [ -d "$d" ] || continue
      install_one "$(basename "$d")"
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
