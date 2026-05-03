#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 <topic> [--squash]" >&2
}

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  usage
  exit 1
fi

topic="$1"
squash=false

if [ "$#" -eq 2 ]; then
  if [ "$2" != "--squash" ]; then
    usage
    exit 1
  fi
  squash=true
fi

WORKTREE_PR_BASE="${WORKTREE_PR_BASE:-origin/main}"
WORKTREE_PR_PREFIX="${WORKTREE_PR_PREFIX:-${USER}/}"
WORKTREE_PR_DIR="${WORKTREE_PR_DIR:-worktrees/}"

BRANCH="${WORKTREE_PR_PREFIX}${topic}"
WDIR="${WORKTREE_PR_DIR}${topic}"

STATE=$(gh pr view "$BRANCH" --json state --jq '.state')
if [ "$STATE" != "MERGED" ]; then
  echo "PR is not merged (state: $STATE); aborting." >&2
  exit 1
fi

MAIN_ROOT=$(git worktree list --porcelain | awk 'NR==1{getline; print $2}')
IFS='/' read -r REMOTE BASE_BRANCH <<< "$WORKTREE_PR_BASE"

git -C "$MAIN_ROOT" pull --ff-only "$REMOTE" "$BASE_BRANCH"
git -C "$MAIN_ROOT" worktree remove "$WDIR"

if [ "$squash" = true ]; then
  git -C "$MAIN_ROOT" branch -D "$BRANCH"
else
  git -C "$MAIN_ROOT" branch -d "$BRANCH"
fi

git -C "$MAIN_ROOT" push origin --delete "$BRANCH"
