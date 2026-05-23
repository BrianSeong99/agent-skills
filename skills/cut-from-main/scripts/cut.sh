#!/usr/bin/env bash
# cut.sh — branch off origin/main, handling master→main rename if needed.
#
# Usage:
#   cut.sh <branch-name> [--auto-rename] [--base <ref>]
#   cut.sh --help
#
# Flags:
#   --auto-rename   Skip the master→main confirmation prompt.
#   --base <ref>    Use <ref> as the base instead of origin/main (bypasses all
#                   default-branch detection).
#   --help          Print this help and exit 0.
#
# Exit codes:
#   0   Branch created successfully.
#   1   Error (see stderr).
#
set -euo pipefail

# ── helpers ──────────────────────────────────────────────────────────────────

die()  { echo "error: $*" >&2; exit 1; }
warn() { echo "warning: $*" >&2; }
info() { echo "$*"; }

usage() {
  awk '/^# cut\.sh/{found=1} found && /^[^#]/{exit} found{sub(/^# ?/,""); print}' "$0"
  exit 0
}

# ── parse arguments ───────────────────────────────────────────────────────────

BRANCH_NAME=""
AUTO_RENAME=0
BASE_REF=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      usage
      ;;
    --auto-rename)
      AUTO_RENAME=1
      shift
      ;;
    --base)
      [[ $# -ge 2 ]] || die "--base requires an argument"
      BASE_REF="$2"
      shift 2
      ;;
    --*)
      die "unknown flag: $1"
      ;;
    *)
      if [[ -z "$BRANCH_NAME" ]]; then
        BRANCH_NAME="$1"
      else
        die "unexpected argument: $1"
      fi
      shift
      ;;
  esac
done

[[ -n "$BRANCH_NAME" ]] || die "branch name required. Usage: cut.sh <branch-name> [--auto-rename] [--base <ref>]"

# ── preflight: git repo ───────────────────────────────────────────────────────

git rev-parse --git-dir > /dev/null 2>&1 \
  || die "not inside a git repository (run from inside your project)"

# ── preflight: origin remote ──────────────────────────────────────────────────

git remote get-url origin > /dev/null 2>&1 \
  || die "no remote named 'origin' found. Add one with: git remote add origin <url>"

# ── --base override path ──────────────────────────────────────────────────────

if [[ -n "$BASE_REF" ]]; then
  info "Using explicit base: $BASE_REF"
  git fetch origin "${BASE_REF#origin/}" 2>/dev/null || warn "fetch of '$BASE_REF' failed — using local tracking ref"
  git checkout -b "$BRANCH_NAME" "$BASE_REF"
  info "Branch $BRANCH_NAME cut from $BASE_REF."
  exit 0
fi

# ── detect default branch ─────────────────────────────────────────────────────

DEFAULT_BRANCH=""

# Attempt 1: symbolic-ref (works when git knows origin/HEAD)
if git symbolic-ref refs/remotes/origin/HEAD > /dev/null 2>&1; then
  DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD --short | sed 's|^origin/||')
fi

# Attempt 2: gh API (needs gh to be logged in)
if [[ -z "$DEFAULT_BRANCH" ]]; then
  if command -v gh > /dev/null 2>&1 && gh auth status > /dev/null 2>&1; then
    DEFAULT_BRANCH=$(gh api repos/:owner/:repo --jq .default_branch 2>/dev/null || true)
  fi
fi

if [[ -z "$DEFAULT_BRANCH" ]]; then
  die "Could not detect default branch. Set it manually with: git remote set-head origin --auto
Or pass --base <ref> to skip detection."
fi

# ── route by default branch ───────────────────────────────────────────────────

case "$DEFAULT_BRANCH" in

  # ── main: happy path ─────────────────────────────────────────────────────────
  main)
    git fetch origin main
    git checkout -b "$BRANCH_NAME" origin/main
    info "Branch $BRANCH_NAME cut from origin/main."
    ;;

  # ── master: rename or refuse ──────────────────────────────────────────────────
  master)
    echo ""
    echo "This repo's default branch is 'master'."
    echo "House rule: every branch is cut from 'main'. No exceptions."
    echo ""

    if [[ "$AUTO_RENAME" -eq 0 ]]; then
      # Interactive prompt
      read -r -p "Rename master → main now? [y/N] " answer < /dev/tty
      case "$answer" in
        [yY]|[yY][eE][sS]) : ;;
        *) die "Refusing to cut from 'master'. Re-run with --auto-rename to rename automatically, or rename manually first." ;;
      esac
    else
      echo "--auto-rename set — proceeding with rename."
    fi

    echo ""
    echo "Renaming master → main …"

    # Sync master locally
    git fetch origin master
    git checkout master
    git pull --ff-only

    # Rename local branch
    git branch -m master main

    # Push new main, update remote tracking
    git push -u origin main

    # Update GitHub default branch (best-effort; non-fatal)
    if command -v gh > /dev/null 2>&1 && gh auth status > /dev/null 2>&1; then
      gh repo edit --default-branch main \
        && info "GitHub default branch updated to 'main'." \
        || warn "gh repo edit failed — update GitHub default branch manually in Settings → Branches."
    else
      warn "gh not logged in — update GitHub default branch manually in Settings → Branches."
    fi

    # Delete old master on remote
    git push origin --delete master

    echo ""
    echo "Rename complete."
    echo ""

    # Now cut the branch
    git fetch origin main
    git checkout -b "$BRANCH_NAME" origin/main
    info "Branch $BRANCH_NAME cut from origin/main."
    ;;

  # ── anything else: refuse unless --base was passed ───────────────────────────
  *)
    die "Default branch is '$DEFAULT_BRANCH', not 'main'.
House rule only allows branching from 'main'.
Options:
  1. Pass --base origin/$DEFAULT_BRANCH to branch from the current default.
  2. Rename the default branch to 'main' manually and re-run.
     (For master, this script can handle the rename — rename your default to 'master' first,
      or run: git remote set-head origin --auto  if origin already points to main.)"
    ;;

esac
