#!/usr/bin/env bash
# start-pr.sh <topic>
#
# Phase 1 of the worktree-pr-flow ritual:
#   1. git fetch origin
#   2. git worktree add <DIR>/<topic> -b <PREFIX><topic> <BASE>
#   3. echo absolute path to stdout for the user to cd into.
#
# Env (all optional):
#   WORKTREE_PR_BASE   (default: origin/main)
#   WORKTREE_PR_PREFIX (default: ${USER}/, e.g. brian/)
#   WORKTREE_PR_DIR    (default: worktrees, relative to repo root)
#
# Exit codes:
#   0 = success
#   1 = generic failure (git error, etc.)
#   2 = bad invocation (missing topic, not in a repo, slug invalid)
#   3 = collision (worktree dir or branch already exists)

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: start-pr.sh <topic>

<topic> is a kebab-case slug (lowercase letters, digits, hyphens; <=40 chars).
EOF
  exit 2
}

topic="${1:-}"
[ -n "$topic" ] || usage

# Validate slug.
if ! printf '%s' "$topic" | grep -Eq '^[a-z0-9][a-z0-9-]{0,39}$'; then
  echo "start-pr: invalid topic slug '$topic' — use lowercase kebab-case, <=40 chars, no leading hyphen" >&2
  exit 2
fi

# Must be inside a git repo.
repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "start-pr: not inside a git repo" >&2
  exit 2
}

base="${WORKTREE_PR_BASE:-origin/main}"
prefix="${WORKTREE_PR_PREFIX:-${USER}/}"
dir_rel="${WORKTREE_PR_DIR:-worktrees}"
# Strip any trailing slash for consistency.
dir_rel="${dir_rel%/}"

branch="${prefix}${topic}"
worktree_path="${repo_root}/${dir_rel}/${topic}"

# Refuse to clobber an existing worktree dir.
if [ -e "$worktree_path" ]; then
  echo "start-pr: worktree path already exists: $worktree_path" >&2
  echo "          remove it first or pick a different topic." >&2
  exit 3
fi

# Refuse to clobber an existing local branch.
if git -C "$repo_root" show-ref --verify --quiet "refs/heads/${branch}"; then
  echo "start-pr: branch already exists locally: ${branch}" >&2
  echo "          delete it first (git branch -d ${branch}) or pick a different topic." >&2
  exit 3
fi

# Make sure base is fresh. Allow user to pre-fetch by setting WORKTREE_PR_NO_FETCH=1.
if [ "${WORKTREE_PR_NO_FETCH:-0}" != "1" ]; then
  remote="${base%%/*}"
  # If base has no remote prefix (e.g. just "main"), skip the fetch.
  if [ "$remote" != "$base" ]; then
    echo "[fetch] git fetch ${remote}" >&2
    git -C "$repo_root" fetch "$remote" --quiet
  fi
fi

# Verify the base ref exists.
if ! git -C "$repo_root" rev-parse --verify --quiet "${base}^{commit}" >/dev/null; then
  echo "start-pr: base ref does not exist: ${base}" >&2
  echo "          set WORKTREE_PR_BASE to a valid ref, or fetch the remote." >&2
  exit 1
fi

# Make sure the parent dir for the worktree exists.
mkdir -p "${repo_root}/${dir_rel}"

echo "[worktree] git worktree add ${worktree_path} -b ${branch} ${base}" >&2
git -C "$repo_root" worktree add "$worktree_path" -b "$branch" "$base"

# Final summary on stdout — meant to be parsed if needed.
printf '%s\n' "$worktree_path"

cat >&2 <<EOF

Worktree ready:
  path:   ${worktree_path}
  branch: ${branch}
  base:   ${base}

Next:
  1. cd "${worktree_path}"
  2. Make your changes.
  3. Run checks: bash ~/.claude/skills/worktree-pr-flow/scripts/run-checks.sh
  4. Push and open PR (ask Claude, or run gh pr create manually).
EOF
