#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 <topic>" >&2
  echo "topic must match ^[a-z0-9][a-z0-9-]*$" >&2
}

if [ "$#" -ne 1 ]; then
  usage
  exit 1
fi

topic="$1"

if [[ ! "$topic" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  usage
  exit 1
fi

WORKTREE_PR_BASE="${WORKTREE_PR_BASE:-origin/main}"
WORKTREE_PR_PREFIX="${WORKTREE_PR_PREFIX:-${USER}/}"
WORKTREE_PR_DIR="${WORKTREE_PR_DIR:-worktrees/}"

BRANCH="${WORKTREE_PR_PREFIX}${topic}"
WDIR="${WORKTREE_PR_DIR}${topic}"

git fetch origin

if git show-ref --verify --quiet "refs/heads/${BRANCH}"; then
  echo "branch already exists: $BRANCH" >&2
  exit 1
fi

if [ -d "$WDIR" ]; then
  echo "worktree dir already exists: $WDIR" >&2
  exit 1
fi

git worktree add "$WDIR" -b "$BRANCH" "$WORKTREE_PR_BASE"
echo "$(cd "$WDIR" && pwd)"
